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
    module Type
      Error = 1

      Create  = 11
      Stop    = 12
      Destroy = 13
      Info    = 14

      Spawn  = 21
      Link   = 22
      Run    = 23
      Stream = 24

      NetIn  = 31
      NetOut = 32

      CopyIn  = 41
      CopyOut = 42

      LimitMemory = 51
      LimitDisk   = 52
      LimitBandwidth  = 53

      Ping = 91
      List = 92
      Echo = 93

      def self.generate_klass_map(suffix)
        map = Hash[self.constants.map do |name|
          klass_name = "#{name}#{suffix}"
          if Protocol.const_defined?(klass_name)
            [const_get(name), Protocol.const_get(klass_name)]
          end
        end]

        if map.respond_to?(:default_proc=)
          map.default_proc = lambda do |h, k|
            raise "Unknown request type: #{k}"
          end
        end

        map
      end

      def self.to_request_klass(type)
        @request_klass_map ||= generate_klass_map("Request")
        @request_klass_map[type]
      end

      def self.to_response_klass(type)
        @response_klass_map ||= generate_klass_map("Response")
        @response_klass_map[type]
      end
    end

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
        return "#{protocol_type.constants.join(", ")}"
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

    class BaseMessage
      include Beefcake::Message

      def safe
          yield
        rescue WrongTypeError, InvalidValueError, RequiredFieldNotSetError => e
          raise ProtocolError, e
      end

      def reload
        safe do
          self.class.decode(encode)
        end
      end

      class << self
        def type
          Type.const_get(type_name)
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

    class BaseRequest < BaseMessage
      def create_response(attributes = {})
        klass_name = self.class.name.gsub(/Request$/, "Response")
        klass_name = klass_name.split("::").last
        klass = Protocol.const_get(klass_name)
        klass.new(attributes)
      end

      def wrap
        safe do
          WrappedRequest.new(:type => self.class.type, :payload => encode)
        end
      end

      def self.description
        type_underscored.gsub("_", " ").capitalize
      end
    end

    class BaseResponse < BaseMessage
      def ok?
        !error?
      end

      def error?
        self.class.type == Type::Error
      end

      def wrap
        safe do
          WrappedResponse.new(:type => self.class.type, :payload => encode)
        end
      end
    end

    class WrappedRequest < BaseRequest
      required :type, Type, 1
      required :payload, :string, 2

      def request
        safe do
          Type.to_request_klass(type).decode(payload)
        end
      end
    end

    class WrappedResponse < BaseResponse
      required :type, Type, 1
      required :payload, :string, 2

      def response
        safe do
          Type.to_response_klass(type).decode(payload)
        end
      end
    end
  end
end
