# coding: UTF-8

require "warden/protocol"
require "forwardable"

module Warden::Repl
  module CommandsManager

    # Raised when an erroneous command is detected.
    class CommandError < StandardError
    end

    # Raised when an erroneous command-line flag is detected.
    class FlagError < CommandError
    end

    # Raised when an erroneous command-line flag element is detected.
    class FlagElementError < CommandError
    end

    # Raised when an error is detected during serialization of
    # a response from the warden server.
    class SerializationError < CommandError
    end

    # Represents an individual element of a command-line flag and directly maps
    # to a field defined in the protocol buffer definition of the related
    # command. For example, in the command-line flag: '--field[0].xxx.yyy[0]',
    # each element viz. 'field[0]', 'xxx', 'yyy[0]' is represented by an object
    # of this class.
    class FlagElement
      attr_reader :name, :index

      class << self
        # First character should be alphabet or underscore, followed by
        # alphabets or digits or underscores. This can be optionally followed
        # by indexing.
        #
        # Sample positives: 'a', 'A', '_', 'aA', '_a', 'a01__A', '_aA[0]',
        #                   '_aA012[1]' etc.
        # Sample negatives: 'a[0.5], a[-1], 'a[blah]', '[1]' etc.
        def flag_element_regex
          /^([a-z_]+[a-z0-9]*)(\[(\d+)\])?$/i
        end
      end

      def initialize(flag_element_str)
        if match = flag_element_str.match(self.class.flag_element_regex)
          @name, _, @index = match.captures
          @index = Integer(@index) if @index
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
    end

    # Represents a command-line flag. Maintains a list of FlagElement objects
    # representing each flag element.
    #
    # Example: An object of this class can represent the flags:
    #          '--field.xxx.yyy', '--field[0].xxx.yyy[1]' etc.
    class Flag
      attr_reader :elements
      extend Forwardable
      def_delegators :@elements, :each, :each_with_index

      def initialize(flag_str, delimiter = ".")
        parsed = parse_flag(flag_str)

        # Parse individual flag elements.
        begin
          @elements = parsed.split(delimiter).map do |element|
            FlagElement.new(element)
          end
        rescue FlagElementError => fle
          raise FlagError, "In flag: '#{flag_str}', #{fle.message}"
        end
      end

      private

      def parse_flag(flag_with_hyphens)
        if match = flag_with_hyphens.match(self.class.flag_regex)
          return match.captures[0]
        end

        raise FlagError, "Invalid flag: '#{flag_with_hyphens}'."
      end

      class << self
        def flag_regex
          /^--([^\s]+)/
        end

        def valid_flag?(flag_str)
          !flag_str.match(flag_regex).nil?
        end

        def help_flag?(flag_str)
          flag_str &&
            (flag_str.downcase == "--help" || flag_str.downcase == "help")
        end
      end
    end

    def command_descriptions
      @desc_map ||= {
        "copy_in" => "Copy files/directories into the container.",
        "copy_out" => "Copy files/directories out of the container.",
        "create" => "Create a container, optionally pass options.",
        "destroy" => "Shutdown a container.",
        "echo" => "Echo a message.",
        "info" => "Show metadata for a container.",
        "limit_cpu" => "Set or get the CPU limit in shares for the container.",
        "limit_disk" => "set or get the disk limit for the container.",
        "limit_memory" => "Set or get the memory limit for the container.",
        "link" => "Do blocking read on results from a job.",
        "list" => "List containers.",
        "net_in" => "Forward port on external interface to container.",
        "net_out" => "Allow traffic from the container to address.",
        "ping" => "Ping warden.",
        "run" => "Short hand for spawn(link(cmd)) i.e. spawns a command, links to the result.",
        "spawn" => "Spawns a command inside a container and returns the job id.",
        "stop" => "Stop all processes inside a container.",
        "stream" => "Do blocking stream on results from a job.",
      }
    end

    # Deserializes a command and its arguments into an object of the
    # corresponding protocol buffer definition class of the command.
    #
    # Params:
    # - command_args [Array of Strings]:
    #      Array where first element is the command name and other elements are
    #      arguments to the command (supplied via command line).
    # - field_delim [String]:
    #      Optional field delimiter that separates fields (flag elements)
    #      defined in each argument in the above array.
    #
    # Returns:
    # - nil:
    #      Returned when the command_args represent a global help command, so
    #      there is nothing to be deserialized and there are no errors.
    # - Hash:
    #      Returned when the command_args contained the 'help' flag. The hash
    #      is a description of the command which can be prettified by the
    #      caller to display help for the command.
    # - Object of a subbclass of Warden::Protocol::BaseRequest:
    #      A protocol buffer object dynamically constructed and populated from
    #      command_args passed.
    #
    # Raises:
    # - Warden::CommandsManager::CommandError:
    #      When command and/or its arguments are wrong.
    # - ArgumentError
    #      When arguments to this method are wrong.
    def deserialize(command_args, field_delim = ".")
      if command_args.empty?
        raise ArgumentError, "Command arguments should be non-empty."
      end

      cmd_name = command_args.shift.downcase
      # Return if the first element is a help flag instead of a command name.
      return if Flag.help_flag?(cmd_name)

      @klass_map = generate_commands_map unless @klass_map
      unless @klass_map.has_key?(cmd_name)
        raise CommandError, "Command: '#{cmd_name}' is non-existent."
      end

      # Generate help for this command if required.
      command_args.each do |arg|
        if Flag.valid_flag?(arg) && Flag.help_flag?(arg)
          return generate_help(@klass_map[cmd_name],
                               :field_delim => field_delim)
        end
      end

      populate_request(@klass_map[cmd_name].new, command_args, field_delim)
    end

    # Serializes a protocol buffer message into a hash.
    #
    # Params:
    # - pb_handle [Warden::Protocol::BaseMessage]:
    #      Protocol buffer message to be serialized.
    #
    # Returns:
    #    Hash with each key being the name [String] of the field defined in the
    #    protocol buffer message and its value being the value of the field
    #    defined in the protocol buffer message.
    #
    # Raises:
    # - Warden::CommandsManager::SerializationError:
    #      When there is an error in serializing the protocl buffer message.
    def serialize(pb_handle, field_delim = ".")
      do_serialize(pb_handle, field_delim)
    end

    # Converts a run command to a spawn command.
    #
    # Params:
    # - run_command [Warden::Protocol::RunRequest]:
    #      Run command to be converted.
    #
    # Returns:
    #    Spawn command [Warden::Protocol::SpawnRequest] with fields having same
    #    values as the run command passed as parameter to this method.
    def convert_to_spawn_command(run_command)
      spawn_command = Warden::Protocol::SpawnRequest.new

      clone = Warden::Protocol::RunRequest.decode(run_command.encode)
      clone.fields.each_value do |field|
        value = clone.send("#{field.name}")
        spawn_command.send("#{field.name}=", value) if value
      end

      spawn_command
    end

    # Generates a stream command from a spawn command and its response.
    #
    # Params:
    # - spawn_command [Warden::Protocol::SpawnRequest]:
    #      Spawn command.
    # - spawn_response [Warden::Protocol::SpawnResponse]:
    #      Spawn response.
    def generate_stream_command(spawn_command, spawn_response)
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

    def to_type(klass)
      type = klass.name.gsub(/(Request|Response)$/, "")
      type = type.split("::").last
      type = type.gsub(/(.)([A-Z])/, "\\1_\\2").downcase
      type
    end

    def generate_help(cmd_type, opts = {})
      help = do_generate_help(cmd_type, opts)
      { to_type(cmd_type).to_sym => help }
    end

    # Generates help for a command type recursively.
    def do_generate_help(cmd_type, opts = {})
      help = {}
      help[:description] = command_descriptions[to_type(cmd_type)]

      help_generator = lambda do |field, prefix|
        field_str = ""
        suffix = ""

        if field.rule == :repeated
          field_str = "#{prefix}#{field.name.to_s}[index]"
          suffix = "  # array"
        else
          field_str = "#{prefix}#{field.name.to_s}"
          suffix = "  # #{field.rule}"
        end

        unless field.type == :bool
          type_str = Warden::Protocol::protocol_type_to_str(field.type)
          field_str << " <#{field.name.to_s}> (#{type_str})" if type_str
          if field.respond_to?(:default)
            suffix << " (default: #{field.default.to_s})"
          end
        end

        field_str = "[#{field_str}]" if field.rule == :optional
        field_str << suffix
        field_str
      end

      cmd_type.fields.values.each do |field|
        help[field.rule] ||= {}
        prefix = opts[:nested] ? opts[:field_delim] : "--"

        if protobuf_field?(field)
          nested_help = do_generate_help(field.type, :nested => true,
                                         :field_delim => opts[:field_delim])
          help[field.rule][field.name] = nested_help
          nested_desc = help_generator.call(field, prefix)
          help[field.rule][field.name][:description] = nested_desc
        else
          help[field.rule][field.name] = help_generator.call(field, prefix)
        end
      end

      help
    end

    # Serializes a protocol buffer message recursively.
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
      obj.fields.each_value do |field_info|
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
            msg = "Cannot serialize enum field: #{field_name}. #{eee.message}"
            raise SerializationError, msg
          end
        else
          serialized[field_name] = do_serialize(field)
        end
      end

      serialized
    end

    # Looks up the name of a constant defined in a Module, based on its value.
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
      klass_map = {}
      map = Warden::Protocol::Message::Type.generate_klass_map("Request")
      map.each_value { |value| klass_map[to_type(value)] = value }
      klass_map
    end

    # For all fields defined in the protocol buffer request object, returns
    # a hash with each key being a field name and value being the field
    # definition.
    def get_fields_map(request)
      fields_map = {}
      request.fields.each_value do |field|
        fields_map[field.name.to_s] = field
      end

      fields_map
    end

    def check_field_exists(flag_str, fields, element)
      unless fields.has_key?(element.name)
        msg = "In flag: '#{flag_str}', the field: '#{element}' is invalid."
        raise FlagError, msg
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
        msg = "In flag: '#{flag_str}'"
        msg << ", the field: '#{element}' is not indexed correctly."
        raise FlagError, msg
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

    def safe_convert
      yield
    rescue ArgumentError, TypeError => e
      raise CommandError, e.message
    end

    # Populates a protocol buffer request object with the arguments.
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
            # Ensure that indexing is correct for repeated field.
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
            if !next_arg || Flag.valid_flag?(next_arg)
              raise FlagError, "Invalid flag: '#{flag_str}'."
            end

            safe_convert do
              list[field_index] = Warden::Protocol::to_ruby_type(next_arg,
                                                                 field_type)
            end

            # This is done to prevent parsing of this value as a command-line
            # flag in the next iteration.
            dont_parse = true
          end
        else
          if field_type == :bool
            pb_handle.send("#{field_name}=", true)
          else
            next_arg = arguments[arg_index + 1]
            if !next_arg || Flag.valid_flag?(next_arg)
              raise FlagError, "Invalid flag: '#{flag_str}'."
            end

            safe_convert do
              pb_handle.send("#{field_name}=",
                             Warden::Protocol::to_ruby_type(next_arg,
                                                            last_parsed[:type]))
            end

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
