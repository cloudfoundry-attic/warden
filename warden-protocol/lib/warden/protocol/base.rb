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
      :bool => lambda do |arg|
        if arg.downcase == "true"
          return true
        elsif arg.downcase == "false"
          return false
        end
        raise ArgumentError, "Expected 'true' or 'false', but received: '#{arg}'."
      end,

      :int32 => lambda do |arg|
        Integer(arg)
      end,

      :uint32 => lambda do |arg|
        Integer(arg)
      end,

      :sint32 => lambda do |arg|
        Integer(arg)
      end,

      :int64 => lambda do |arg|
        Integer(arg)
      end,

      :uint64 => lambda do |arg|
        Integer(arg)
      end,

      :fixed32 => lambda do |arg|
        Float(arg)
      end,

      :sfixed32 => lambda do |arg|
        Float(arg)
      end,

      :float => lambda do |arg|
        Float(arg)
      end,

      :fixed64 => lambda do |arg|
        Float(arg)
      end,

      :sfixed64 => lambda do |arg|
        Float(arg)
      end,

      :double => lambda do |arg|
        Float(arg)
      end,

      :string =>  lambda do |arg|
        String(arg)
      end
    }

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

      def reload
        self.class.decode(encode)
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
        WrappedRequest.new(:type => self.class.type, :payload => encode)
      end

      def self.description
        raise NotImplementedError
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
        WrappedResponse.new(:type => self.class.type, :payload => encode)
      end
    end

    class WrappedRequest < BaseRequest
      required :type, Type, 1
      required :payload, :string, 2

      def request
        Type.to_request_klass(type).decode(payload)
      end
    end

    class WrappedResponse < BaseResponse
      required :type, Type, 1
      required :payload, :string, 2

      def response
        Type.to_response_klass(type).decode(payload)
      end
    end
  end
end
