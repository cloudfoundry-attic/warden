# coding: UTF-8

require "warden/network"
require "warden/pool/base"

module Warden

  module Pool

    class Network < Base

      attr_reader :pooled_netmask

      # The release delay can be used to postpone address being acquired again
      # after being released. This can be used to make sure the kernel has time
      # to clean up things such as lingering connections.

      def initialize(network, options = {})
        address = network[%r!^(.*)/!, 1]
        netmask = network[%r!/(\d+)$!, 1]

        if address.nil? || netmask.nil?
          raise "Invalid address/netmask (require: 1.2.3.4/5)"
        end

        to_netmask = lambda do |size|
          ~((2**(32-size))-1) & 0xffffffff
        end

        address = Warden::Network::Address.new(address)
        netmask = Warden::Network::Netmask.new(to_netmask.call(netmask.to_i))
        pooled_netmask = Warden::Network::Netmask.new(to_netmask.call(30))
        count = netmask.size / pooled_netmask.size

        @start_address = address.network(pooled_netmask)
        @end_address = @start_address + (pooled_netmask.size * (count - 1))
        @pooled_netmask = pooled_netmask

        options[:release_delay] ||= 5.0

        super(count, options) do |i|
          @start_address + pooled_netmask.size * i
        end
      end

      private

      def belongs?(addr)
        (addr >= @start_address) && (addr <= @end_address)
      end
    end
  end
end
