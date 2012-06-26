require "warden/protocol/base"

module Warden
  module Protocol
    class RunReq < BaseReq
      required :handle, :string, 1
      required :script, :string, 2
      optional :privileged, :bool, 3, :default => false
    end

    class RunRep < BaseRep
      optional :exit_status, :uint32, 1
      optional :stdout, :string, 2
      optional :stderr, :string, 3
    end
  end
end
