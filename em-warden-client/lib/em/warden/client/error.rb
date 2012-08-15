module EventMachine
  module Warden
    module Client
      class Error < StandardError
      end

      class ConnectionError < Error
      end
    end
  end
end
