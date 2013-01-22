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

      def initialize(start, count, options = {})
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
        super(count, options) do |i|
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
