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

        def do_limit_disk(request, response)
          if request.block_limit || request.inode_limit
            limits = []

            limits << 0                        # soft block limit
            limits << request.block_limit.to_i # hard block limit
            limits << 0                        # soft inode limit
            limits << request.inode_limit.to_i # hard inode limit

            if limits.any? { |e| e > 0 }
              args  = ["setquota"]
              args += ["-u", uid.to_s]
              args += limits.map(&:to_s)
              args += [container_depot_mount_point_path]
              sh *args
            end
          end

          # Return current limits
          repquota = self.class.repquota(uid)
          response.block_limit = repquota[uid][:quota][:block][:hard]
          response.inode_limit = repquota[uid][:quota][:inode][:hard]

          nil
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

          def repquota(uids)
            uids = [uids] unless uids.kind_of?(Enumerable)

            return {} if uids.empty?

            repquota_path = Warden::Util.path("src/repquota/repquota")
            args  = [repquota_path]
            args += [@container_depot_mount_point_path]
            args += uids.map(&:to_s)

            output = sh *args

            usage = {}
            output.lines.each do |line|
              fields = line.split(/\s+/)
              fields = fields.map {|f| f.to_i }
              usage[fields[0]] = {
                :usage => {
                  :block => fields[1],
                  :inode => fields[5],
                },
                :quota => {
                  :block => {
                    :soft => fields[2],
                    :hard => fields[3],
                  },
                  :inode => {
                    :soft => fields[6],
                    :hard => fields[7],
                  },
                },
              }
            end

            usage
          end
        end
      end
    end
  end
end
