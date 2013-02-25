# coding: UTF-8

require "warden/protocol/base"
require "warden/protocol/resource_limits"

module Warden
  module Protocol
    class SpawnRequest
      include Warden::Protocol::BaseMessage

      required :handle, :string, 1
      required :script, :string, 2
      optional :privileged, :bool, 3, :default => false
      optional :rlimits, ResourceLimits, 4

      def self.description
        "Spawns a command inside a container and returns the job id."
      end
    end

    class SpawnResponse
      include Warden::Protocol::BaseMessage

      required :job_id, :uint32, 1
    end
  end
end
