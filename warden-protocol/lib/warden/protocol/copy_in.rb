# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class CopyInRequest
      include Warden::Protocol::BaseMessage

      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3

      def self.description
        "Copy files/directories into the container."
      end
    end

    class CopyInResponse
      include Warden::Protocol::BaseMessage
    end
  end
end
