require "warden/protocol/base"

module Warden
  module Protocol
    class InfoReq < BaseReq
      required :handle, :string, 1
    end

    class InfoRep < BaseRep
      optional :state, :string, 10

      repeated :events, :string, 20

      optional :host_ip,      :string, 30
      optional :container_ip, :string, 31
    end
  end
end
