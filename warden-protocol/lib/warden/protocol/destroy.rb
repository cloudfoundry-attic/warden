# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class DestroyRequest < BaseRequest
      required :handle, :string, 1

      def self.description
        "Shutdown a container."
      end
    end

    class DestroyResponse < BaseResponse
    end
  end
end
