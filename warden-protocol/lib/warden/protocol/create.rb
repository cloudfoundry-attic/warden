# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class CreateRequest < BaseRequest
      class BindMount < BaseMessage
        module Mode
          RO = 0
          RW = 1
        end

        required :src_path, :string, 1
        required :dst_path, :string, 2
        required :mode, BindMount::Mode, 3
      end

      repeated :bind_mounts, BindMount, 1
      optional :grace_time, :uint32, 2

      def self.description
        "Create a container, optionally pass options."
      end
    end

    class CreateResponse < BaseResponse
      required :handle, :string, 1
    end
  end
end
