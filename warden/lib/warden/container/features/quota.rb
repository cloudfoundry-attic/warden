require "warden/errors"
require "warden/container/spawn"

require "sys/filesystem"

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

        def before_create(request, response)
          super

          # Reset quota limits
          setquota(uid, [0, 0, 0, 0])
        end

        def do_limit_disk(request, response)
          if request.block_limit || request.inode_limit
            limits = []

            limits << 0                        # soft block limit
            limits << request.block_limit.to_i # hard block limit
            limits << 0                        # soft inode limit
            limits << request.inode_limit.to_i # hard inode limit

            if limits.any? { |e| e > 0 }
              setquota(uid, limits)
            end
          end

          # Return current limits
          repquota = self.class.repquota(uid)
          response.block_limit = repquota[uid][:quota][:block][:hard]
          response.inode_limit = repquota[uid][:quota][:inode][:hard]

          nil
        end

        private

        def setquota(uid, limits)
          args  = ["setquota"]
          args += ["-u", uid.to_s]
          args += limits.map(&:to_s)
          args += [container_depot_mount_point_path]
          sh *args
        end

        module ClassMethods

          include Spawn

          def container_depot_mount_point_path
            @container_depot_mount_point_path ||=
              Sys::Filesystem.mount_point(container_depot_path)
          end

          def repquota(uids)
            uids = [uids] unless uids.kind_of?(Enumerable)

            return {} if uids.empty?

            repquota_path = Warden::Util.path("src/repquota/repquota")
            args  = [repquota_path]
            args += [container_depot_mount_point_path]
            args += uids.map(&:to_s)

            output = sh *args

            usage = Hash.new do |h, k|
              h[k] = {
                :usage => {
                  :block => 0,
                  :inode => 0,
                },
                :quota => {
                  :block => {
                    :soft => 0,
                    :hard => 0,
                  },
                  :inode => {
                    :soft => 0,
                    :hard => 0,
                  },
                },
              }
            end

            output.lines.each do |line|
              fields = line.split(/\s+/)
              fields = fields.map {|f| f.to_i }
              uid = fields[0]

              usage[uid][:usage][:block] = fields[1]
              usage[uid][:usage][:inode] = fields[5]
              usage[uid][:quota][:block][:soft] = fields[2]
              usage[uid][:quota][:block][:hard] = fields[3]
              usage[uid][:quota][:inode][:soft] = fields[6]
              usage[uid][:quota][:inode][:hard] = fields[7]
            end

            usage
          end
        end
      end
    end
  end
end
