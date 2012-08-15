# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LimitBandwidthRequest < BaseRequest
      required :handle, :string, 1
      required :rate, :uint64, 2
      required :burst, :uint64, 3
    end

    class LimitBandwidthResponse < BaseResponse
      required :rate, :uint64, 1
      required :burst, :uint64, 2
    end
  end
end
