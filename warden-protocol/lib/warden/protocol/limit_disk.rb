require "warden/protocol/base"

module Warden
  module Protocol
    class LimitDiskReq < BaseReq
      required :handle, :string, 1
      optional :block_limit, :uint32, 10
      optional :inode_limit, :uint32, 20
    end

    class LimitDiskRep < BaseRep
      optional :block_limit, :uint32, 10
      optional :inode_limit, :uint32, 20
    end
  end
end
