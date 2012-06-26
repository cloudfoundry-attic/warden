require "warden/protocol/base"

module Warden
  module Protocol
    class ListRequest < BaseRequest
    end

    class ListResponse < BaseResponse
      repeated :handles, :string, 1
    end
  end
end
