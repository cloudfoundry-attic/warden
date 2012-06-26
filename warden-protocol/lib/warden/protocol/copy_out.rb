require "warden/protocol/base"

module Warden
  module Protocol
    class CopyOutReq < BaseReq
      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3
      optional :owner, :string, 4
    end

    class CopyOutRep < BaseRep
    end
  end
end
