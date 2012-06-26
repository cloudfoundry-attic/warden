require "warden/protocol/base"

module Warden
  module Protocol
    class StopReq < BaseReq
      required :handle, :string, 1
    end

    class StopRep < BaseRep
    end
  end
end
