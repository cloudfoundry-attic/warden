# coding: UTF-8

require "warden/protocol"
require "forwardable"

module Warden
  module CommandsManager

    class CommandError < StandardError
    end

    class FlagError < CommandError
    end

    class FlagElementError < CommandError
    end

    class SerializationError < CommandError
    end

    class FlagElement
      attr_reader :name, :index

      class << self
        def var_regex
          "[a-zA-Z_][a-zA-Z_0-9]*"
        end

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
        return other.name == name && other.index == index
      end

      private

      def get_index(index_str)
        index_str = index_str.gsub("[","").gsub("]","")
        Integer(index_str)
      end
    end

    class Flag
      attr_reader :elements
      extend Forwardable
      def_delegators :@elements, :each, :each_with_index

      def initialize(flag_str, delimiter = ".")
        unless flag_str.is_a?(String)
          raise ArgumentError, "Expected argument to be of type: #{String}, but received: #{flag_str.class}."
        end

        parsed_flag_str = parse_flag(flag_str)
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
      command_args.each do |arg|
        if Flag.is_valid_flag(arg) && Flag.is_help_flag(arg)
          return :command_help, generate_help(@klass_map[cmd_name])
        end
      end

      return cmd_name.to_sym, populate_request(@klass_map[cmd_name].new,
                                               command_args, field_delim)
    end

    def serialize(pb_handle, field_delim = ".")
      unless pb_handle.is_a?(Warden::Protocol::BaseMessage)
        raise ArgumentError, "Expected protocol buffer object to be of type: #{Warden::Protocol::BaseMessage}, but received: #{pb_handle.class}."
      end

      do_serialize(pb_handle, field_delim)
    end

    private

    class EnumEncodingError < StandardError
    end

    def generate_help(cmd_type, nested = false, field_delim = ".")
      help = do_generate_help(cmd_type, nested, field_delim)
      { cmd_type.type_underscored.to_sym => help }
    end

    def do_generate_help(cmd_type, nested = false, field_delim = ".")
      help = {}
      help[:description] = command_descriptions[cmd_type.type_underscored]

      field_str_generator = lambda do |field, prefix|
        field_str = ""
        case field.rule
        when :required
          field_str = "#{prefix}#{field.name.to_s}"
        when :optional
          field_str = "[#{prefix}#{field.name.to_s}]"
        when :repeated
          field_str = "#{prefix}#{field.name.to_s}[index]"
        end

        if field.type != :bool
          type_str = Warden::Protocol::protocol_type_to_str(field.type)
          field_str << " <#{field.name.to_s}> (#{type_str})" if type_str
          field_str << " (default: #{field.default.to_s})" if field.respond_to?(:default)
        end

        field_str
      end

      [:required, :optional, :repeated].each do |type|
        fields = cmd_type.fields.values.find_all do |f|
          f.rule == type
        end

        unless fields.empty?
          help[type] = {}
          fields.each do |f|
            prefix = nested ? field_delim : "--"
            if protobuf_field?(f)
              help[type][f.name] = do_generate_help(f.type, true, field_delim)
              help[type][f.name][:description] = field_str_generator.call(f, prefix)
            else
              help[type][f.name] = field_str_generator.call(f, prefix)
            end
          end
        end
      end

      help
    end

    def do_serialize(obj, field_delim = ".")
      if !obj.is_a?(Warden::Protocol::BaseMessage)
        return obj.to_s
      end

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
            raise EnumEncodingError, "Duplicate constants defined in module: #{type}."
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

    def populate_request(request, arguments, field_delim = ".")
      next_arg_index = nil
      pb_handle = last_parsed_field = nil

      arguments.each_with_index do |flag_str, arg_index|
        next if next_arg_index && arg_index < next_arg_index

        flag = Flag.new(flag_str, field_delim)
        pb_handle = request
        last_parsed = {}
        fields = get_fields_map(pb_handle)

        flag.each do |element|
          unless fields.has_key?(element.name)
            raise FlagError, "In flag: '#{flag_str}', the field: '#{element}' is invalid."
          end

          field = fields[element.name]
          if field.rule == :repeated
            unless element.index
              raise FlagError, "In flag: '#{flag_str}', the field: '#{element}' is not indexed."
            end

            unless list = pb_handle.send("#{element.name}")
              list = []
              pb_handle.send("#{element.name}=", list)
            end

            unless element.index == list.size ||
                element.index == list.size - 1
              raise FlagError, "In flag: '#{flag_str}', the field: '#{element}' is not indexed correctly."
            end

            if protobuf_field?(field)
              if element.index == list.size
                list[element.index] = field.type.new
              end

              pb_handle = list[element.index]
              fields = get_fields_map(pb_handle)
              last_parsed.clear
            else
              last_parsed[:field] = element
              last_parsed[:type] = field.type
            end
          else
            if protobuf_field?(field)
              unless nested_pb = pb_handle.send("#{element.name}")
                nested_pb = field.type.new
                pb_handle.send("#{element.name}=", nested_pb)
              end

              pb_handle = nested_pb
              fields = get_fields_map(pb_handle)
              last_parsed.clear
            else
              last_parsed[:field] = element
              last_parsed[:type] = field.type
            end
          end
        end

        unless last_parsed[:field] && last_parsed[:type]
          raise FlagError, "Invalid flag: '#{flag_str}'."
        end

        if last_parsed[:field].index
          list = pb_handle.send("#{last_parsed[:field].name}")
          field_index = last_parsed[:field].index
          if last_parsed[:type] == :bool
            list[field_index] = true
          else
            next_arg_index = arg_index + 1
            if next_arg_index == arguments.size ||
                Flag.is_valid_flag(arguments[next_arg_index])
              raise FlagError, "Invalid flag: '#{flag_str}'."
            end
            list[field_index] = Warden::Protocol::to_ruby_type(arguments[next_arg_index],
                                                               last_parsed[:type])
            next_arg_index += 1
          end
        else
          name = last_parsed[:field].name
          if last_parsed[:type] == :bool
            pb_handle.send("#{name}=", true)
          else
            next_arg_index = arg_index + 1
            if next_arg_index == arguments.size ||
                Flag.is_valid_flag(arguments[next_arg_index])
              raise FlagError, "Invalid flag: '#{flag_str}'."
            end

            pb_handle.send("#{name}=",
                           Warden::Protocol::to_ruby_type(arguments[next_arg_index],
                                                          last_parsed[:type]))
            next_arg_index += 1
          end
        end
      end

      request
    end

    def protobuf_field?(field_info)
      field_info.type.is_a?(Class) &&
        field_info.type.ancestors.include?(Warden::Protocol::BaseMessage)
    end
  end
end
