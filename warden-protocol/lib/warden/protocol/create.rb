require "warden/protocol/base"

module Warden
  module Protocol
    class CreateReq < BaseReq
      class BindMount < BaseMessage
        module Mode
          RO = 0
          RW = 1
        end

        required :src, :string, 1
        required :dst, :string, 2
        required :mode, BindMount::Mode, 3
      end

      repeated :bind_mounts, BindMount, 1
      optional :grace_time, :uint32, 2

      def self.from_repl_v1(args)
        new.tap do |instance|
          args.each do |e|
            head, tail = e.split(":", 2)

            case head
            when "bind_mount"
              src, dst, mode = tail.split(",")
              mode = BindMount::Mode.const_get(mode.upcase)

              instance.bind_mounts ||= []
              instance.bind_mounts << BindMount.new(
                :src => src,
                :dst => dst,
                :mode => mode)

            when "grace_time"
              instance.grace_time = Integer(tail)

            when "disk_size_mb"
              # Deprecated

            else
              raise "Unknown argument: #{head}"
            end
          end
        end
      end
    end

    class CreateRep < BaseRep
      required :handle, :string, 1
    end
  end
end
