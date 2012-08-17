# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class StopRequest < BaseRequest
      required :handle, :string, 1
      optional :background, :bool, 10
      optional :kill, :bool, 20

      def self.description
        "Stop all processes inside a container."
      end
    end

    class StopResponse < BaseResponse
    end
  end
end
