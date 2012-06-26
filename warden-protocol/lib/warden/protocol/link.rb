require "warden/protocol/base"

module Warden
  module Protocol
    class LinkReq < BaseReq
      required :handle, :string, 1
      required :job_id, :uint32, 2
    end

    class LinkRep < BaseRep
      optional :exit_status, :uint32, 1
      optional :stdout, :string, 2
      optional :stderr, :string, 3
    end
  end
end
