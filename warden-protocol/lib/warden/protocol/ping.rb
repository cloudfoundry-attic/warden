# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class PingRequest < BaseRequest
      def self.description
        "Ping warden."
      end
    end

    class PingResponse < BaseResponse
    end
  end
end
