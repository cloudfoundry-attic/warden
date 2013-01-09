# coding: UTF-8

require "set"

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

      def delete(*entries)
        entry_set = Set.new(entries)
        @pool.delete_if { |e| entry_set.include?(e[1]) }
        nil
      end

      def acquire
        time, entry = @pool.first

        if time == nil || time < Time.now
          @pool.shift
          return entry
        end

        return nil
      end

      def fetch(entry)
        pair = @pool.find do |e|
          e[1] == entry && (e[0] == nil || e[0] < Time.now)
        end

        if pair
          @pool.delete(pair)
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
