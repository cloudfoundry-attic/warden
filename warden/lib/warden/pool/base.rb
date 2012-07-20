# coding: UTF-8

module Warden

  module Pool

    class Base

      # The release delay can be used to postpone the entry being
      # acquired again after being release.
      attr_reader :release_delay

      def initialize(count, options = {})
        @pool = []
        @release_delay = options.delete(:release_delay) || 0.0

        if block_given?
          @pool = count.times.map { |i| [nil, yield(i)] }
        end
      end

      def size
        @pool.size
      end

      def acquire
        time, entry = @pool.first

        if time == nil || time < Time.now
          @pool.shift
          return entry
        end

        return nil
      end

      def release(entry)
        return unless belongs?(entry)

        @pool.push [Time.now + @release_delay, entry]
      end

      private

      def belongs?(entry)
        true
      end
    end
  end
end
