require "beefcake"

module Warden
  module Protocol
    module Type
      Error = 1

      Create  = 11
      Stop    = 12
      Destroy = 13
      Info    = 14

      Spawn = 21
      Link  = 22
      Run   = 23

      NetIn  = 31
      NetOut = 32

      CopyIn  = 41
      CopyOut = 42

      LimitMemory = 51
      LimitDisk   = 52

      Ping = 91
      List = 92

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
        @request_klass_map ||= generate_klass_map("Req")
        @request_klass_map[type]
      end

      def self.to_reply_klass(type)
        @reply_klass_map ||= generate_klass_map("Rep")
        @reply_klass_map[type]
      end
    end

    class BaseMessage
      include Beefcake::Message

      def reload
        self.class.decode(encode)
      end
    end

    class BaseReq < BaseMessage
      def create_reply(attributes = {})
        klass_name = self.class.name.gsub(/Req$/, "Rep")
        klass_name = klass_name.split("::").last
        klass = Protocol.const_get(klass_name)
        klass.new(attributes)
      end

      def wrap
        klass_name = self.class.name.gsub(/Req$/, "")
        klass_name = klass_name.split("::").last

        WrappedReq.new \
          :type => Type.const_get(klass_name),
          :payload => encode
      end
    end

    class BaseRep < BaseMessage
      def wrap
        klass_name = self.class.name.gsub(/Rep$/, "")
        klass_name = klass_name.split("::").last

        WrappedRep.new \
          :type => Type.const_get(klass_name),
          :payload => encode
      end
    end

    class WrappedReq < BaseReq
      required :type, Type, 1
      required :payload, :string, 2

      def request
        Type.to_request_klass(type).decode(payload)
      end
    end

    class WrappedRep < BaseRep
      required :type, Type, 1
      required :payload, :string, 2

      def reply
        Type.to_reply_klass(type).decode(payload)
      end
    end
  end
end
