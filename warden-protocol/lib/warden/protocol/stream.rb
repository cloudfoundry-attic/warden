# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class StreamRequest < BaseRequest
      required :handle, :string, 1
      required :job_id, :uint32, 2

      def self.description
        "Do blocking stream on results from a job."
      end
    end

    class StreamResponse < BaseResponse
      optional :name, :string, 1
      optional :data, :string, 2
      optional :exit_status, :uint32, 3
    end
  end
end
