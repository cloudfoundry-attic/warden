# coding: UTF-8

require "warden/errors"
require "warden/pool/base"

module Warden

  module Pool

    class Port < Base

      class NoLoopDeviceAvailable < WardenError

        def message
          super || "no loop device available"
        end
      end

      def initialize(options = {})
        # to be done
      end

      def acquire
        # to be done
      end

      private

      def belongs?(num)
        # to be done
      end
    end
  end
end
