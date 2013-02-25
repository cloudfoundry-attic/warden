# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LimitMemoryRequest
      include Warden::Protocol::BaseMessage

      required :handle, :string, 1
      optional :limit_in_bytes, :uint64, 2

      def self.description
        "Set or get the memory limit for the container."
      end
    end

    class LimitMemoryResponse
      include Warden::Protocol::BaseMessage

      optional :limit_in_bytes, :uint64, 1
    end
  end
end
