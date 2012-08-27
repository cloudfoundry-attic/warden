# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class InfoRequest < BaseRequest
      required :handle, :string, 1

      def self.description
        "Show metadata for a container."
      end
    end

    class InfoResponse < BaseResponse
      class MemoryStat < BaseMessage
        optional :cache, :uint64, 1
        optional :rss, :uint64, 2
        optional :mapped_file, :uint64, 3
        optional :pgpgin, :uint64, 4
        optional :pgpgout, :uint64, 5
        optional :swap, :uint64, 6
        optional :pgfault, :uint64, 7
        optional :pgmajfault, :uint64, 8
        optional :inactive_anon, :uint64, 9
        optional :active_anon, :uint64, 10
        optional :inactive_file, :uint64, 11
        optional :active_file, :uint64, 12
        optional :unevictable, :uint64, 13
        optional :hierarchical_memory_limit, :uint64, 14
        optional :hierarchical_memsw_limit, :uint64, 15
        optional :total_cache, :uint64, 16
        optional :total_rss, :uint64, 17
        optional :total_mapped_file, :uint64, 18
        optional :total_pgpgin, :uint64, 19
        optional :total_pgpgout, :uint64, 20
        optional :total_swap, :uint64, 21
        optional :total_pgfault, :uint64, 22
        optional :total_pgmajfault, :uint64, 23
        optional :total_inactive_anon, :uint64, 24
        optional :total_active_anon, :uint64, 25
        optional :total_inactive_file, :uint64, 26
        optional :total_active_file, :uint64, 27
        optional :total_unevictable, :uint64, 28
      end

      class CpuStat < BaseMessage
        optional :usage,  :uint64, 1 # Nanoseconds
        optional :user,   :uint64, 2 # Hz (USER_HZ specifically)
        optional :system, :uint64, 3 # Hz
      end

      class DiskStat < BaseMessage
        optional :bytes_used,  :uint64, 1
        optional :inodes_used, :uint64, 2
      end

      class BandwidthStat < BaseMessage
        optional :in_rate, :uint64, 1
        optional :in_burst, :uint64, 2
        optional :out_rate, :uint64, 3
        optional :out_burst, :uint64, 4
      end

      optional :state, :string, 10

      repeated :events, :string, 20

      optional :host_ip,      :string, 30
      optional :container_ip, :string, 31
      optional :container_path, :string, 32

      optional :memory_stat, MemoryStat, 40
      optional :cpu_stat, CpuStat, 41
      optional :disk_stat, DiskStat, 42
      optional :bandwidth_stat, BandwidthStat, 43
    end
  end
end
