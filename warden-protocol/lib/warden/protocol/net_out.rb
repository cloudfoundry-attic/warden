require "warden/protocol/base"

module Warden
  module Protocol
    class NetOutRequest < BaseRequest
      required :handle, :string, 1
      optional :network, :string, 2
      optional :port, :uint32, 3
    end

    class NetOutResponse < BaseResponse
    end
  end
end
