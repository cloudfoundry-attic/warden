# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class DetachImageRequest < BaseRequest
      required :handle, :string, 1
      required :image_path, :string, 2 # outside of container

      def self.description
        "Detach a disk image from the container."
      end
    end

    class DetachImageResponse < BaseResponse
      required :exit_status, :uint32, 1
      optional :message, :string, 2
    end
  end
end
