# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LimitBandwidthRequest < BaseRequest
      required :handle, :string, 1 # Bandwidth rate in byte(s)/sec
      required :rate,   :uint64, 2 # Allow burst size in byte(s)
      required :burst,  :uint64, 3
    end

    class LimitBandwidthResponse < BaseResponse
      required :rate,  :uint64, 1 # Bandwidth rate in byte(s)/sec
      required :burst, :uint64, 2 # Allow burst size in byte(s)
    end
  end
end
