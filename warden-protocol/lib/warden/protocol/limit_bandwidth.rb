# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LimitBandwidthRequest < BaseRequest
      required :handle, :string, 1
      #bandwidth rate in byte(s)/sec
      required :rate, :uint64, 2
      #allow burst size in byte(s)
      required :burst, :uint64, 3
    end

    class LimitBandwidthResponse < BaseResponse
      #bandwidth rate in byte(s)/sec
      required :rate, :uint64, 1
      #allow burst size in byte(s)
      required :burst, :uint64, 2
    end
  end
end
