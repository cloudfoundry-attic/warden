require "warden/protocol/base"

module Warden
  module Protocol
    class SpawnRequest < BaseRequest
      required :handle, :string, 1
      required :script, :string, 2
      optional :privileged, :bool, 3, :default => false
    end

    class SpawnResponse < BaseResponse
      required :job_id, :uint32, 1
    end
  end
end
