# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class ListRequest
      include Warden::Protocol::BaseMessage

      def self.description
        "List containers."
      end
    end

    class ListResponse
      include Warden::Protocol::BaseMessage

      repeated :handles, :string, 1
    end
  end
end
