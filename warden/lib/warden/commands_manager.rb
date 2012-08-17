# coding: UTF-8

require "warden/protocol"
require "forwardable"

module Warden
  module CommandsManager

    # Raised when an erroneous command is detected.
    class CommandError < StandardError
    end

    # Raised when an erroneous command-line flag is detected.
    class FlagError < CommandError
    end

    # Raised when an erroneous command-line element flag is detected.
    class FlagElementError < CommandError
    end

    # Raised when an error is detected during serialization of
    # a response from the warden server.
    class SerializationError < CommandError
    end

    # Represents an individual element of a command-line flag and directly maps
    # to a field defined in the protocol buffer definition of the related
    # command. For example, in the command-line flag: '--field.xxx.yyy', each
    # element viz. 'field', 'xxx', 'yyy' is represented by an object of this
    # class.
    class FlagElement
      attr_reader :name, :index

      class << self
        # First character should be alphabet or underscore, followed by
        # alphabets or digits or underscores.
        #
        # Positives: 'a', 'A', 'aA', 'aa', 'aA012__A' etc.
        # Negatives: '-', '-a', '_a' et
        def var_regex
          "[a-zA-Z_][a-zA-Z_0-9]*"
        end

        # Positives: '[0]', '[1]', '[5]' etc.
        # Negatives: '[0.5]', '[-1]', '[blah]' etc.
        def indexing_regex
          "(\\\[[\\d]+\\\]){0,1}"
        end

        def flag_element_regex
          "^(#{var_regex})(#{indexing_regex})$"
        end
      end

      def initialize(flag_element_str)
        unless flag_element_str.is_a?(String)
          raise ArgumentError, "Expected argument to be of type: #{String}, but received: #{flag_element_str.class}."
        end

        if match = flag_element_str.match(self.class.flag_element_regex)
          @name, index = match.captures
          @index = get_index(index) if index and !index.empty?
        else
          raise FlagElementError, "Invalid flag element: '#{flag_element_str}'."
        end
      end

      def to_s
        return "#{name}[#{@index}]" if @index
        "#{name}"
      end

      def ==(other)
        return false unless other && other.is_a?(self.class)
        other.name == name && other.index == index
      end

      private

      def get_index(index_str)
        index_str = index_str.gsub("[","").gsub("]","")
        Integer(index_str)
      end
    end

    # Represents a command-line flag. Maintains a list of FlagElement objects
    # representing each flag element.
    #
    # Example: An object of this class can represent the flag: '--field.xxx.yyy'
    class Flag
      attr_reader :elements
      extend Forwardable
      def_delegators :@elements, :each, :each_with_index

      def initialize(flag_str, delimiter = ".")
        unless flag_str.is_a?(String)
          raise ArgumentError, "Expected argument to be of type: #{String}, but received: #{flag_str.class}."
        end

        parsed_flag_str = parse_flag(flag_str)

        # Parse individual flag elements.
        @elements = []
        parsed_flag_str.split(delimiter).each do |element|
          begin
            @elements << FlagElement.new(element)
          rescue FlagElementError => fle
            raise FlagError, "In flag: '#{flag_str}', #{fle.message}"
          end
        end
      end

      private

      def parse_flag(flag_with_hifens)
        if match = flag_with_hifens.match(self.class.flag_regex)
          return match.captures[0]
        end

        raise FlagError, "Invalid flag: '#{flag_with_hifens}'."
      end

      class << self
        def flag_regex
          return "--([^\\s]+)"
        end

        def is_valid_flag(flag_str)
          return !flag_str.match(flag_regex).nil?
        end

        def is_help_flag(flag_str)
          flag_str &&
            (flag_str.downcase == "--help" || flag_str.downcase == "help")
        end
      end
    end

    # If not previously generated, generates a hash with each key being the
    # string representation of a command and value being the description
    # defined in the protocol buffee request definition corresponding to that
    # command.
    def command_descriptions
      unless @desc_map
        @klass_map = generate_commands_map unless @klass_map
        @desc_map = {}
        @klass_map.each_pair do |key, value|
          @desc_map[key] = value.description
        end
      end

      @desc_map.freeze
    end

    # Deserializes a command and its arguments into an object of the
    # corresponding protocol buffer definition class of the command.
    def deserialize(command_args, field_delim = ".")
      unless command_args.is_a?(Array)
        raise ArgumentError, "Expected argument to be of type: #{Array}, but received: #{command_args.class}."
      end

      if command_args.empty?
        raise ArgumentError, "Command arguments should be non-empty."
      end

      cmd_name = command_args[0]
      cmd_name = cmd_name.downcase
      # Return if the first element is a help flag instead of a command name.
      if Flag.is_help_flag(cmd_name)
        return :help
      end

      @klass_map = generate_commands_map unless @klass_map
      unless @klass_map.has_key?(cmd_name)
        raise CommandError, "Command: '#{cmd_name}' is non-existent."
      end

      command_args = command_args.slice(1..-1)
      # Generate help for this command if required.
      command_args.each do |arg|
        if Flag.is_valid_flag(arg) && Flag.is_help_flag(arg)
          return :command_help, generate_help(@klass_map[cmd_name],
                                              :field_delim => field_delim)
        end
      end

      return cmd_name.to_sym, populate_request(@klass_map[cmd_name].new,
                                               command_args, field_delim)
    end


    # Serializes a protocol buffer message into a hash with keys and values
    # being string representations of the names of fields and their values.
    def serialize(pb_handle, field_delim = ".")
      unless pb_handle.is_a?(Warden::Protocol::BaseMessage)
        msg = "Expected protocol buffer object to be of type:"
        msg << " #{Warden::Protocol::BaseMessage}, but received:"
        msg << " #{pb_handle.class}."

        raise ArgumentError, msg
      end

      do_serialize(pb_handle, field_delim)
    end

    def convert_to_spawn_command(run_command)
      unless run_command.is_a?(Warden::Protocol::RunRequest)
        msg = "Expected protocol buffer object to be of type:"
        msg << " #{Warden::Protocol::RunRequest}, but received:"
        msg << " #{run_command.class}."

        raise ArgumentError, msg
      end

      copy_fields(run_command, Warden::Protocol::SpawnRequest.new)
    end

    def generate_stream_command(spawn_command, spawn_response)
      unless spawn_command.is_a?(Warden::Protocol::SpawnRequest)
        msg = "Expected protocol buffer object to be of type:"
        msg << " #{Warden::Protocol::SpawnRequest}, but received:"
        msg << " #{spawn_command.class}."

        raise ArgumentError, msg
      end

      unless spawn_response.is_a?(Warden::Protocol::SpawnResponse)
        msg = "Expected protocol buffer object to be of type:"
        msg << " #{Warden::Protocol::SpawnResponse}, but received:"
        msg << " #{spawn_response.class}."

        raise ArgumentError, msg
      end

      stream_request = Warden::Protocol::StreamRequest.new
      stream_request.handle = spawn_command.handle.dup
      stream_request.job_id = spawn_response.job_id
      stream_request
    end

    private

    # Raised when an enum cannot be serialized due to ambiguity in its
    # definition.
    class EnumEncodingError < StandardError
    end

    def copy_fields(pb_handle_A, pb_handle_B)
      pb_handle_A.fields.each_pair do |key, field|
        value = pb_handle_A.send("#{field.name}")
        pb_handle_B.send("#{field.name}=", value.dup) if value
      end

      pb_handle_B
    end

    def generate_help(cmd_type, opts = {})
      help = do_generate_help(cmd_type, opts)
      { cmd_type.type_underscored.to_sym => help }
    end

    def do_generate_help(cmd_type, opts = {})
      help = {}
      help[:description] = command_descriptions[cmd_type.type_underscored]

      help_generator = lambda do |field, prefix|
        field_str = ""
        suffix = ""

        case field.rule
        when :required
          field_str = "#{prefix}#{field.name.to_s}"
          suffix = "  # #{field.rule}"
        when :optional
          field_str = "[#{prefix}#{field.name.to_s}]"
          suffix = "  # #{field.rule}"
        when :repeated
          field_str = "#{prefix}#{field.name.to_s}[index]"
          suffix = "  # array"
        end

        unless field.type == :bool
          type_str = Warden::Protocol::protocol_type_to_str(field.type)

          if type_str
            field_str << " <#{field.name.to_s}> (#{type_str})"
          end

          if field.respond_to?(:default)
            field_str << " (default: #{field.default.to_s})"
          end
        end

        field_str << suffix
        field_str
      end

      [:required, :optional, :repeated].each do |type|
        fields = cmd_type.fields.values.find_all { |f| f.rule == type }

        unless fields.empty?
          help[type] = {}
          fields.each do |field|
            prefix = opts[:nested] ? opts[:field_delim] : "--"
            if protobuf_field?(field)
              nested_help = do_generate_help(field.type,
                                             :nested => true,
                                             :field_delim => opts[:field_delim])
              help[type][field.name] = nested_help
              help[type][field.name][:description] = help_generator.call(field,
                                                                         prefix)
            else
              help[type][field.name] = help_generator.call(field,
                                                           prefix)
            end
          end
        end
      end

      help
    end

    def do_serialize(obj, field_delim = ".")
      return obj.to_s if !obj.is_a?(Warden::Protocol::BaseMessage)

      append_serialized = lambda do |key, source, target_hash, field_delim|
        if source.is_a?(Hash)
          source.each_pair do |source_key, source_value|
            target_hash["#{key}#{field_delim}#{source_key}"] = source_value
          end
        else
          target_hash["#{key}"] = source
        end
      end

      serialized = {}
      obj.fields.each_pair do |key, field_info|
        field_name = "#{field_info.name.to_s}"
        field = obj.send(field_name)
        next if !field

        if field_info.rule == :repeated
          field.each_with_index do |e, index|
            append_serialized.call("#{field_name}[#{index}]",
                                   do_serialize(e, field_delim),
                                   serialized, field_delim)
          end
        elsif protobuf_field?(field_info)
          # Flatten nested protocol buffer fields.
          append_serialized.call(field_name, do_serialize(field, field_delim),
                                 serialized, field_delim)
        elsif field_info.type.is_a?(Module) # enum field
          begin
            serialized[field_name] = get_constant(field_info.type, field)
          rescue EnumEncodingError => eee
            raise SerializationError, "Cannot serialize enum field: #{field_name}. #{eee.message}"
          end
        else
          serialized[field_name] = do_serialize(field)
        end
      end

      serialized
    end

    def get_constant(type, value)
      to_return = nil
      type.constants.each do |constant|
        if type.const_get(constant) == value
          if to_return
            msg = "Duplicate constants defined in module: #{type}."
            raise EnumEncodingError,  msg
          end

          to_return = constant.to_s
        end
      end

      to_return
    end

    def generate_commands_map
      map = Warden::Protocol::Type.generate_klass_map("Request")
      klass_map = {}
      map.each_pair do |key, value|
        klass_map[value.type_underscored] = value
      end

      klass_map
    end

    def get_fields_map(request)
      fields_map = {}
      request.fields.each_pair do |key, field|
        fields_map[field.name.to_s] = field
      end

      fields_map
    end

    def check_field_exists(flag_str, fields, element)
      unless fields.has_key?(element.name)
        raise FlagError, "In flag: '#{flag_str}', the field: '#{element}' is invalid."
      end
    end

    def check_indexing_exists(flag_str, element)
      unless element.index
        msg = "In flag: '#{flag_str}', the field: '#{element}' is not indexed."
        raise FlagError, msg
      end
    end

    def check_indexing(flag_str, list, element)
      unless element.index == list.size ||
          element.index == list.size - 1
        raise FlagError, "In flag: '#{flag_str}', the field: '#{element}' is not indexed correctly."
      end
    end

    def initialize_list(pb_handle, element)
      unless list = pb_handle.send("#{element.name}")
        list = []
        pb_handle.send("#{element.name}=", list)
      end

      list
    end

    def initialize_pb(list, element, type)
      if element.index == list.size
        list[element.index] = type.new
      end

      list[element.index]
    end

    def initialize_nested_pb(pb_handle, element, type)
      unless nested_pb = pb_handle.send("#{element.name}")
        nested_pb = type.new
        pb_handle.send("#{element.name}=", nested_pb)
      end

      nested_pb
    end

    def protobuf_field?(field)
      field.type.is_a?(Class) &&
        field.type.ancestors.include?(Warden::Protocol::BaseMessage)
    end

    def populate_request(request, arguments, field_delim = ".")
      # Handle to the proto buf object that will be populated with a value.
      pb_handle = nil
      # Name of field and its type to be populated into pb_handle.
      last_parsed = {}
      dont_parse = false

      arguments.each_with_index do |flag_str, arg_index|
        if dont_parse
          dont_parse = false
          next
        end

        flag = Flag.new(flag_str, field_delim)
        pb_handle = request
        last_parsed.clear
        fields = get_fields_map(pb_handle)

        flag.each do |element|
          check_field_exists(flag_str, fields, element)

          field = fields[element.name]
          if field.rule == :repeated
            # Ensure that indexing is correct of repeated field.
            check_indexing_exists(flag_str, element)
            list = initialize_list(pb_handle, element)
            check_indexing(flag_str, list, element)

            if protobuf_field?(field)
              pb_handle = initialize_pb(list, element, field.type)
              fields = get_fields_map(pb_handle)
              # Clear last_parsed to catch erroneous command-line flags.
              last_parsed.clear
            else
              last_parsed[:element] = element
              last_parsed[:type] = field.type
            end
          else
            if protobuf_field?(field)
              pb_handle = initialize_nested_pb(pb_handle, element, field.type)
              fields = get_fields_map(pb_handle)
              # Clear last_parsed to catch erroneous command-line flags.
              last_parsed.clear
            else
              last_parsed[:element] = element
              last_parsed[:type] = field.type
            end
          end
        end

        # We cannot populate pb_handle without reference to a field and type.
        unless last_parsed[:element] && last_parsed[:type]
          raise FlagError, "Invalid flag: '#{flag_str}'."
        end

        field_index = last_parsed[:element].index
        field_name = last_parsed[:element].name
        field_type = last_parsed[:type]

        # Populating repeated fields is different from simple fields.
        if field_index
          list = pb_handle.send("#{field_name}")
          if field_type == :bool
            list[field_index] = true
          else
            next_arg = arguments[arg_index + 1]
            if !next_arg || Flag.is_valid_flag(next_arg)
              raise FlagError, "Invalid flag: '#{flag_str}'."
            end

            list[field_index] = Warden::Protocol::to_ruby_type(next_arg,
                                                               field_type)
            # This is done to prevent parsing of this value as a command-line
            # flag in the next iteration.
            dont_parse = true
          end
        else
          if field_type == :bool
            pb_handle.send("#{field_name}=", true)
          else
            next_arg = arguments[arg_index + 1]
            if !next_arg || Flag.is_valid_flag(next_arg)
              raise FlagError, "Invalid flag: '#{flag_str}'."
            end

            pb_handle.send("#{field_name}=",
                           Warden::Protocol::to_ruby_type(next_arg,
                                                          last_parsed[:type]))
            # This is done to prevent parsing of this value as a command-line
            # flag in the next iteration.
            dont_parse = true
          end
        end
      end

      request
    end
  end
end
