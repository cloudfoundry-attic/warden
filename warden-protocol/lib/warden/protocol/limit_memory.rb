require "warden/protocol/base"

module Warden
  module Protocol
    class LimitMemoryRequest < BaseRequest
      required :handle, :string, 1
      optional :limit_in_bytes, :uint64, 2
    end

    class LimitMemoryResponse < BaseResponse
      optional :limit_in_bytes, :uint64, 1
    end
  end
end
