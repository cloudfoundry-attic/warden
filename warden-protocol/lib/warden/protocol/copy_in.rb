# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class CopyInRequest < BaseRequest
      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3

      def self.description
        "Copy files/directories into the container."
      end
    end

    class CopyInResponse < BaseResponse
    end
  end
end
