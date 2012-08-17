# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class CopyOutRequest < BaseRequest
      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3
      optional :owner, :string, 4

      def self.description
        "Copy files/directories out of the container."
      end
    end

    class CopyOutResponse < BaseResponse
    end
  end
end
