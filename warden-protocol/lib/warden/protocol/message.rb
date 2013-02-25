# coding: UTF-8

require "warden/protocol/base"
require "warden/protocol/type"

module Warden
  module Protocol
    class Message
      include Warden::Protocol::BaseMessage

      required :type, Type, 1
      required :payload, :string, 2

      def request
        safe do
          Type.to_request_klass(type).decode(payload)
        end
      end

      def response
        safe do
          Type.to_response_klass(type).decode(payload)
        end
      end
    end
  end
end
