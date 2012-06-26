require "warden/protocol/base"

module Warden
  module Protocol
    class StopRequest < BaseRequest
      required :handle, :string, 1
    end

    class StopResponse < BaseResponse
    end
  end
end
