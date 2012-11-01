# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class AttachImageRequest < BaseRequest
      required :handle, :string, 1
      required :image_path, :string, 2 # outside of container
      required :device_path, :string, 3 # inside of container

      def self.description
        "Attach a disk image to the container."
      end
    end

    class AttachImageResponse < BaseResponse
      required :exit_status, :uint32, 1
      optional :message, :string, 2
    end
  end
end
