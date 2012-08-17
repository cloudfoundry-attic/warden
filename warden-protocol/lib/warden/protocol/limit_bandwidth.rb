# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LimitBandwidthRequest < BaseRequest
      required :handle, :string, 1
      required :rate,   :uint64, 2 # Bandwidth rate in byte(s)/sec
      required :burst,  :uint64, 3 # Allow burst size in byte(s)
    end

    class LimitBandwidthResponse < BaseResponse
      required :rate,  :uint64, 1 # Bandwidth rate in byte(s)/sec
      required :burst, :uint64, 2 # Allow burst size in byte(s)
    end
  end
end
