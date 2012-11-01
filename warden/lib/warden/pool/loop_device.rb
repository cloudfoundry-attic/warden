# coding: UTF-8

require "warden/errors"
require "warden/pool/base"

module Warden

  module Pool

    class LoopDevice < Base

      class NoLoopDeviceAvailable < WardenError

        def message
          super || "no loop device available"
        end
      end

      def initialize(start, count, options = {})
        @start_num = start
        @end_num = start + count - 1

        super(count) do |i|
          num = start + i

          if occupied?(num)
            fail "Loop device /dev/loop#{num} is busy."
          end

          num
        end
      end

      def acquire
        super.tap do |num|
          raise NoLoopDeviceAvailable unless num
        end
      end

      private

      def occupied?(num)
        `losetup /dev/loop#{num} > /dev/null 2>&1`
        return false if 0 != $?.to_i

        `losetup -d /dev/loop#{num} > /dev/null 2>&1`
        0 != $?.to_i
      end

      def belongs?(num)
        (num >= @start_num) && (num <= @end_num)
      end
    end
  end
end
