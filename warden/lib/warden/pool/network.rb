# coding: UTF-8

require "warden/network"
require "warden/pool/base"

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
        @end_address = @start_address + (@netmask.size * (count - 1))

        options[:release_delay] ||= 5.0

        super(count, options) do |i|
          @start_address + @netmask.size * i
        end
      end

      private

      def belongs?(addr)
        (addr >= @start_address) && (addr <= @end_address)
      end
    end
  end
end
