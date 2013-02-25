# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LimitBandwidthRequest
      include Warden::Protocol::BaseMessage

      required :handle, :string, 1
      optional :rate,   :uint64, 2 # Bandwidth rate in byte(s)/sec
      optional :burst,  :uint64, 3 # Allow burst size in byte(s)
    end

    class LimitBandwidthResponse
      include Warden::Protocol::BaseMessage

      optional :rate,  :uint64, 1 # Bandwidth rate in byte(s)/sec
      optional :burst, :uint64, 2 # Allow burst size in byte(s)
    end
  end
end
