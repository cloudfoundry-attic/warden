require "warden/protocol/base"

module Warden
  module Protocol
    class ListReq < BaseReq
    end

    class ListRep < BaseRep
      repeated :handles, :string, 1
    end
  end
end
