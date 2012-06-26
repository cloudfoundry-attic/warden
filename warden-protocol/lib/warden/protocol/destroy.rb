require "warden/protocol/base"

module Warden
  module Protocol
    class DestroyReq < BaseReq
      required :handle, :string, 1
    end

    class DestroyRep < BaseRep
    end
  end
end
