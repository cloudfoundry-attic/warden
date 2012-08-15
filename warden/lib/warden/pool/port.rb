# coding: UTF-8

require "warden/errors"
require "warden/pool/base"

module Warden

  module Pool

    class Port < Base

      class NoPortAvailable < WardenError

        def message
          super || "no port available"
        end
      end

      def self.ip_local_port_range
        File.read("/proc/sys/net/ipv4/ip_local_port_range").split.map(&:to_i)
      end

      def initialize(options = {})
        ephemeral_start, ephemeral_stop = self.class.ip_local_port_range
        start = ephemeral_stop + 1
        stop = 65000 + 1
        count = stop - start

        # Hardcode the minimum number of ports to 1000
        if count < 1000
          raise WardenError.new \
            "Insufficient non-ephemeral ports available" +
            " (expected >= %d, got: %d)" % [1000, count]
        end

        @start_port = start
        @end_port = start + (count - 1)

        # The port range spanned by [start, stop) does not overlap with the
        # ephemeral port range and will therefore not conflict with ports
        # used by locally originated connection. It is safe to map these
        # ports to containers.
        super(count) do |i|
          start + i
        end
      end

      def acquire
        super.tap do |port|
          raise NoPortAvailable unless port
        end
      end

      private

      def belongs?(port)
        (port >= @start_port) && (port <= @end_port)
      end
    end
  end
end
