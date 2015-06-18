# coding: UTF-8

require "beefcake"

module Beefcake
  class Buffer
    # Patch beefcake to be encoding-agnostic
    def append_string(s)
      if s.respond_to?(:force_encoding)
        s = s.dup.force_encoding("binary")
      end

      append_uint64(s.length)
      self << s
    end
  end
end

module Warden
  module Protocol
    TypeConverter = {
      :bool     => lambda do |arg|
        return true if arg.downcase == "true"
        return false if arg.downcase == "false"
        raise ArgumentError, "Expected 'true' or 'false', but received: '#{arg}'."
      end,

      :int32    => lambda { |arg| Integer(arg) },
      :uint32   => lambda { |arg| Integer(arg) },
      :sint32   => lambda { |arg| Integer(arg) },
      :int64    => lambda { |arg| Integer(arg) },
      :uint64   => lambda { |arg| Integer(arg) },
      :fixed32  => lambda { |arg| Float(arg) },
      :sfixed32 => lambda { |arg| Float(arg) },
      :float    => lambda { |arg| Float(arg) },
      :fixed64  => lambda { |arg| Float(arg) },
      :sfixed64 => lambda { |arg| Float(arg) },
      :double   => lambda { |arg| Float(arg) },
      :string   => lambda { |arg| String(arg) },
    }

    # Used to wrap around Beefcake errors.
    class ProtocolError < StandardError
      attr_reader :cause

      def initialize(cause)
        @cause = cause
      end

      def message
        return @cause.message
      end
    end

    def self.protocol_type_to_str(protocol_type)
      if protocol_type.class == Module
        return "#{protocol_type.constants.sort.join(", ")}"
      elsif protocol_type.is_a?(Symbol)
        return "#{protocol_type.to_s}"
      end

      return nil
    end

    def self.to_ruby_type(str, protocol_type)
      converter = Warden::Protocol::TypeConverter[protocol_type]
      return converter.call(str) if converter

      # Enums are defined as Ruby Modules in Beefcake
      error_msg = nil
      if protocol_type.class == Module
        return protocol_type.const_get(str) if protocol_type.const_defined?(str)
        raise TypeError, "The constant: '#{str}' is not defined in the module: '#{protocol_type}'."
      end

      raise TypeError, "Non-existent protocol type passed: '#{protocol_type}'."
    end

    module BaseMessage
      def self.included(base)
        base.send(:include, Beefcake::Message)

        if base.name =~ /(Request|Response)$/
          base.extend(ClassMethods)

          case $1
          when "Request"
            base.send(:include, BaseRequest)
          when "Response"
            base.send(:include, BaseResponse)
          end
        end
      end

      def safe
        yield
      rescue Beefcake::Message::WrongTypeError,
             Beefcake::Message::InvalidValueError,
             Beefcake::Message::RequiredFieldNotSetError => e
        raise ProtocolError, e
      end

      def reload
        safe do
          self.class.decode(encode)
        end
      end

      def wrap
        safe do
          Message.new(:type => self.class.type, :payload => encode)
        end
      end

      def filtered_fields
        []
      end

      def filtered_hash
        fields = to_hash
        filtered_fields.each { |field| fields.delete(field) }
        fields
      end

      module ClassMethods
        def type
          Message::Type.const_get(type_name)
        end

        def type_camelized
          type_name
        end

        def type_underscored
          type_name.gsub(/(.)([A-Z])/, "\\1_\\2").downcase
        end

        def type_name
          type_name = name.gsub(/(Request|Response)$/, "")
          type_name = type_name.split("::").last
          type_name
        end
      end
    end

    module BaseRequest
      def create_response(attributes = {})
        klass_name = self.class.name.gsub(/Request$/, "Response")
        klass_name = klass_name.split("::").last
        klass = Protocol.const_get(klass_name)
        klass.new(attributes)
      end
    end

    module BaseResponse
      def ok?
        !error?
      end

      def error?
        self.class.type == Message::Type::Error
      end
    end
  end
end

require "warden/protocol/pb"
require "warden/protocol/message"
