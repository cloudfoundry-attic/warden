require "warden/protocol/base"

module Warden
  module Protocol
    class DestroyRequest < BaseRequest
      required :handle, :string, 1
    end

    class DestroyResponse < BaseResponse
    end
  end
end
