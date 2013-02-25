# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class PingRequest
      include Warden::Protocol::BaseMessage

      def self.description
        "Ping warden."
      end
    end

    class PingResponse
      include Warden::Protocol::BaseMessage
    end
  end
end
