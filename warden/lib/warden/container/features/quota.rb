require "warden/errors"
require "warden/container/spawn"

module Warden

  module Container

    module Features

      module Quota

        include Spawn

        def self.included(base)
          base.extend(ClassMethods)
        end

        # Path to the mount point of the file system housing the container depot
        def container_depot_mount_point_path
          @container_depot_mount_point_path ||= self.class.container_depot_mount_point_path
        end

        def get_limit_disk
          limits["disk"] ||= 0
          limits["disk"]
        end

        def set_limit_disk(args)
          unless args.length == 1
            raise WardenError.new("Invalid number of arguments: expected 1, got #{args.length}")
          end

          begin
            block_limit = Integer(args[0])
          rescue
            raise WardenError.new("Invalid limit")
          end

          args  = ["setquota"]
          args += ["-u", uid]

          args << 0           # soft block limit
          args << block_limit # hard block limit
          args << 0           # soft inode limit
          args << 0           # hard inode limit

          args << container_depot_mount_point_path

          sh *args.map(&:to_s)

          limits["disk"] = block_limit

          "ok"
        end

        module ClassMethods

          include Spawn

          attr_reader :container_depot_mount_point_path

          def setup(config = {})
            super(config)

            args  = ["stat"]
            args += ["-c", "%m"]
            args += [container_depot_path]

            stdout = sh *args

            @container_depot_mount_point_path = stdout.chomp
          end
        end
      end
    end
  end
end
