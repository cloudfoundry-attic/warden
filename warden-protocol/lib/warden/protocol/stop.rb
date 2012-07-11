require "warden/protocol/base"

module Warden
  module Protocol
    class StopRequest < BaseRequest
      required :handle, :string, 1
      optional :background, :bool, 10
      optional :kill, :bool, 20
    end

    class StopResponse < BaseResponse
    end
  end
end
