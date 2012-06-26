require "warden/protocol/base"

module Warden
  module Protocol
    class ErrorRep < BaseRep
      optional :message, :string, 2
      optional :data, :string, 4
      repeated :backtrace, :string, 3
    end
  end
end
