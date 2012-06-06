require "warden/pool/base"
require "warden/network"

module Warden

  module Pool

    class Network < Base

      attr_reader :netmask

      # The release delay can be used to postpone address being acquired again
      # after being released. This can be used to make sure the kernel has time
      # to clean up things such as lingering connections.

      def initialize(start_address, count, options = {})
        @start_address = Warden::Network::Address.new(start_address)
        @netmask = Warden::Network::Netmask.new(255, 255, 255, 252)

        options[:release_delay] ||= 5.0

        super(count, options) do |i|
          @start_address + @netmask.size * i
        end
      end
    end
  end
end
