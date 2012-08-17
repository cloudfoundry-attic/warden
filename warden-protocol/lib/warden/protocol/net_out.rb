# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class NetOutRequest < BaseRequest
      required :handle, :string, 1
      optional :network, :string, 2
      optional :port, :uint32, 3

      def self.description
        "Allow traffic from the container to address."
      end
    end

    class NetOutResponse < BaseResponse
    end
  end
end
