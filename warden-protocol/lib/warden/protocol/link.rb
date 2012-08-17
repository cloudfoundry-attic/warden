# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class LinkRequest < BaseRequest
      required :handle, :string, 1
      required :job_id, :uint32, 2

      def self.description
        "Do blocking read on results from a job."
      end
    end

    class LinkResponse < BaseResponse
      optional :exit_status, :uint32, 1
      optional :stdout, :string, 2
      optional :stderr, :string, 3
    end
  end
end
