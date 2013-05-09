## Generated from bundle for protocol
require "beefcake"

module Warden
  module Protocol

    class CopyInRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3

    end

    class CopyInResponse
      include Warden::Protocol::BaseMessage



    end

    class CopyOutRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :src_path, :string, 2
      required :dst_path, :string, 3
      optional :owner, :string, 4

    end

    class CopyOutResponse
      include Warden::Protocol::BaseMessage



    end

    class CreateRequest
      include Warden::Protocol::BaseMessage


      class BindMount
        include Warden::Protocol::BaseMessage

        module Mode
          RO = 0
          RW = 1
        end

        required :src_path, :string, 1
        required :dst_path, :string, 2
        required :mode, CreateRequest::BindMount::Mode, 3

      end

      repeated :bind_mounts, CreateRequest::BindMount, 1
      optional :grace_time, :uint32, 2
      optional :handle, :string, 3
      optional :network, :string, 4
      optional :rootfs, :string, 5

    end

    class CreateResponse
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1

    end

    class DestroyRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1

    end

    class DestroyResponse
      include Warden::Protocol::BaseMessage



    end

    class EchoRequest
      include Warden::Protocol::BaseMessage


      required :message, :string, 1

    end

    class EchoResponse
      include Warden::Protocol::BaseMessage


      required :message, :string, 1

    end

    class ErrorResponse
      include Warden::Protocol::BaseMessage


      optional :message, :string, 2
      optional :data, :string, 4
      repeated :backtrace, :string, 3

    end

    class InfoRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1

    end

    class InfoResponse
      include Warden::Protocol::BaseMessage


      class MemoryStat
        include Warden::Protocol::BaseMessage


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

      class CpuStat
        include Warden::Protocol::BaseMessage


        optional :usage, :uint64, 1
        optional :user, :uint64, 2
        optional :system, :uint64, 3

      end

      class DiskStat
        include Warden::Protocol::BaseMessage


        optional :bytes_used, :uint64, 1
        optional :inodes_used, :uint64, 2

      end

      class BandwidthStat
        include Warden::Protocol::BaseMessage


        optional :in_rate, :uint64, 1
        optional :in_burst, :uint64, 2
        optional :out_rate, :uint64, 3
        optional :out_burst, :uint64, 4

      end

      optional :state, :string, 10
      repeated :events, :string, 20
      optional :host_ip, :string, 30
      optional :container_ip, :string, 31
      optional :container_path, :string, 32
      optional :memory_stat, InfoResponse::MemoryStat, 40
      optional :cpu_stat, InfoResponse::CpuStat, 41
      optional :disk_stat, InfoResponse::DiskStat, 42
      optional :bandwidth_stat, InfoResponse::BandwidthStat, 43
      repeated :job_ids, :uint64, 44

    end

    class LimitBandwidthRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :rate, :uint64, 2
      required :burst, :uint64, 3

    end

    class LimitBandwidthResponse
      include Warden::Protocol::BaseMessage


      required :rate, :uint64, 1
      required :burst, :uint64, 2

    end

    class LimitDiskRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      optional :block_limit, :uint64, 10
      optional :block, :uint64, 11
      optional :block_soft, :uint64, 12
      optional :block_hard, :uint64, 13
      optional :inode_limit, :uint64, 20
      optional :inode, :uint64, 21
      optional :inode_soft, :uint64, 22
      optional :inode_hard, :uint64, 23
      optional :byte_limit, :uint64, 30
      optional :byte, :uint64, 31
      optional :byte_soft, :uint64, 32
      optional :byte_hard, :uint64, 33

    end

    class LimitDiskResponse
      include Warden::Protocol::BaseMessage


      optional :block_limit, :uint64, 10
      optional :block, :uint64, 11
      optional :block_soft, :uint64, 12
      optional :block_hard, :uint64, 13
      optional :inode_limit, :uint64, 20
      optional :inode, :uint64, 21
      optional :inode_soft, :uint64, 22
      optional :inode_hard, :uint64, 23
      optional :byte_limit, :uint64, 30
      optional :byte, :uint64, 31
      optional :byte_soft, :uint64, 32
      optional :byte_hard, :uint64, 33

    end

    class LimitMemoryRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      optional :limit_in_bytes, :uint64, 2

    end

    class LimitMemoryResponse
      include Warden::Protocol::BaseMessage


      optional :limit_in_bytes, :uint64, 1

    end

    class LinkRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :job_id, :uint32, 2

    end

    class LinkResponse
      include Warden::Protocol::BaseMessage


      optional :exit_status, :uint32, 1
      optional :stdout, :string, 2
      optional :stderr, :string, 3
      optional :info, InfoResponse, 4

    end

    class ListRequest
      include Warden::Protocol::BaseMessage



    end

    class ListResponse
      include Warden::Protocol::BaseMessage


      repeated :handles, :string, 1

    end

    class Message
      include Warden::Protocol::BaseMessage

      module Type
        Error = 1
        Create = 11
        Stop = 12
        Destroy = 13
        Info = 14
        Spawn = 21
        Link = 22
        Run = 23
        Stream = 24
        NetIn = 31
        NetOut = 32
        CopyIn = 41
        CopyOut = 42
        LimitMemory = 51
        LimitDisk = 52
        LimitBandwidth = 53
        Ping = 91
        List = 92
        Echo = 93
      end

      required :type, Message::Type, 1
      required :payload, :bytes, 2

    end

    class NetInRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      optional :host_port, :uint32, 3
      optional :container_port, :uint32, 2

    end

    class NetInResponse
      include Warden::Protocol::BaseMessage


      required :host_port, :uint32, 1
      required :container_port, :uint32, 2

    end

    class NetOutRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      optional :network, :string, 2
      optional :port, :uint32, 3

    end

    class NetOutResponse
      include Warden::Protocol::BaseMessage



    end

    class PingRequest
      include Warden::Protocol::BaseMessage



    end

    class PingResponse
      include Warden::Protocol::BaseMessage



    end

    class ResourceLimits
      include Warden::Protocol::BaseMessage


      optional :as, :uint64, 1
      optional :core, :uint64, 2
      optional :cpu, :uint64, 3
      optional :data, :uint64, 4
      optional :fsize, :uint64, 5
      optional :locks, :uint64, 6
      optional :memlock, :uint64, 7
      optional :msgqueue, :uint64, 8
      optional :nice, :uint64, 9
      optional :nofile, :uint64, 10
      optional :nproc, :uint64, 11
      optional :rss, :uint64, 12
      optional :rtprio, :uint64, 13
      optional :sigpending, :uint64, 14
      optional :stack, :uint64, 15

    end

    class RunRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :script, :string, 2
      optional :privileged, :bool, 3, :default => false
      optional :rlimits, ResourceLimits, 4

    end

    class RunResponse
      include Warden::Protocol::BaseMessage


      optional :exit_status, :uint32, 1
      optional :stdout, :string, 2
      optional :stderr, :string, 3
      optional :info, InfoResponse, 4

    end

    class SpawnRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :script, :string, 2
      optional :privileged, :bool, 3, :default => false
      optional :rlimits, ResourceLimits, 4

    end

    class SpawnResponse
      include Warden::Protocol::BaseMessage


      required :job_id, :uint32, 1

    end

    class StopRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      optional :background, :bool, 10, :default => false
      optional :kill, :bool, 20, :default => false

    end

    class StopResponse
      include Warden::Protocol::BaseMessage



    end

    class StreamRequest
      include Warden::Protocol::BaseMessage


      required :handle, :string, 1
      required :job_id, :uint32, 2

    end

    class StreamResponse
      include Warden::Protocol::BaseMessage


      optional :name, :string, 1
      optional :data, :string, 2
      optional :exit_status, :uint32, 3
      optional :info, InfoResponse, 4

    end
  end
end
