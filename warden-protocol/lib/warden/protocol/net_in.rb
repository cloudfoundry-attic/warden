require "warden/protocol/base"

module Warden
  module Protocol
    class NetInRequest < BaseRequest
      required :handle, :string, 1
      optional :container_port, :uint32, 2
    end

    class NetInResponse < BaseResponse
      required :host_port, :uint32, 1
      required :container_port, :uint32, 2
    end
  end
end
