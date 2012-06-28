require "warden/protocol/base"

module Warden
  module Protocol
    class EchoRequest < BaseRequest
      required :message, :string, 1
    end

    class EchoResponse < BaseResponse
      required :message, :string, 1
    end
  end
end
