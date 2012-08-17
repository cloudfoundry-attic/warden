# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class ListRequest < BaseRequest
      def self.description
        "List containers."
      end
    end

    class ListResponse < BaseResponse
      repeated :handles, :string, 1
    end
  end
end
