require "warden/protocol/base"

module Warden
  module Protocol
    class CopyInReq < BaseReq
      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3
    end

    class CopyInRep < BaseRep
    end
  end
end
