# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class DestroyRequest
      include Warden::Protocol::BaseMessage

      required :handle, :string, 1

      def self.description
        "Shutdown a container."
      end
    end

    class DestroyResponse
      include Warden::Protocol::BaseMessage
    end
  end
end
