require "warden/protocol/base"

module Warden
  module Protocol
    class LimitDiskRequest < BaseRequest
      required :handle, :string, 1
      optional :block_limit, :uint32, 10
      optional :inode_limit, :uint32, 20
    end

    class LimitDiskResponse < BaseResponse
      optional :block_limit, :uint32, 10
      optional :inode_limit, :uint32, 20
    end
  end
end
