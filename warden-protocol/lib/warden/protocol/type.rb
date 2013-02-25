# coding: UTF-8

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
  end
end
