require "warden/protocol/base"

module Warden
  module Protocol
    class CreateRequest < BaseRequest
      class BindMount < BaseMessage
        module Mode
          RO = 0
          RW = 1
        end

        required :src, :string, 1
        required :dst, :string, 2
        required :mode, BindMount::Mode, 3
      end

      repeated :bind_mounts, BindMount, 1
      optional :grace_time, :uint32, 2
    end

    class CreateResponse < BaseResponse
      required :handle, :string, 1
    end
  end
end
