require "warden/protocol/base"

module Warden
  module Protocol
    class StreamRequest < BaseRequest
      required :handle, :string, 1
      required :job_id, :uint32, 2
    end

    class StreamResponse < BaseResponse
      optional :name, :string, 1
      optional :data, :string, 2
    end
  end
end
