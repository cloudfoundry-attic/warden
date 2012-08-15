# coding: UTF-8

require "warden/errors"
require "warden/pool/base"

module Warden

  module Pool

    class Uid < Base

      class NoUidAvailable < WardenError

        def message
          super || "no uid available"
        end
      end

      def self.local_uids
        File.readlines("/etc/passwd").map { |e| e.split(":")[2].to_i }.sort
      end

      def initialize(start, count, options = {})
        local_uids = self.class.local_uids

        @start_uid = start
        @end_uid = start + (count - 1)

        super(count) do |i|
          uid = start + i

          if local_uids.include?(uid)
            fail "UID in user pool overlaps with user in /etc/passwd"
          end

          uid
        end
      end

      def acquire
        super.tap do |uid|
          raise NoUidAvailable unless uid
        end
      end

      private

      def belongs?(uid)
        (uid >= @start_uid) && (uid <= @end_uid)
      end
    end
  end
end
