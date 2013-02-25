# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class EchoRequest
      include Warden::Protocol::BaseMessage

      required :message, :string, 1

      def self.description
        "Echo a message."
      end
    end

    class EchoResponse
      include Warden::Protocol::BaseMessage

      required :message, :string, 1
    end
  end
end
