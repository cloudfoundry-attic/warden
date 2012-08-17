# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class NetInRequest < BaseRequest
      required :handle, :string, 1
      optional :container_port, :uint32, 2

      def self.description
        "Forward port #in on external interface to container."
      end
    end

    class NetInResponse < BaseResponse
      required :host_port, :uint32, 1
      required :container_port, :uint32, 2
    end
  end
end
