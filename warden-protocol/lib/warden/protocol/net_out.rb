require "warden/protocol/base"

module Warden
  module Protocol
    class NetOutReq < BaseReq
      required :handle, :string, 1
      optional :network, :string, 2
      optional :port, :uint32, 3
    end

    class NetOutRep < BaseRep
    end
  end
end
