# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class RunRequest < BaseRequest
      required :handle, :string, 1
      required :script, :string, 2
      optional :privileged, :bool, 3, :default => false

      def self.description
        "Short hand for spawn(link(cmd)) i.e. spawns a command, links to the result."
      end
    end

    class RunResponse < BaseResponse
      optional :exit_status, :uint32, 1
      optional :stdout, :string, 2
      optional :stderr, :string, 3
    end
  end
end
