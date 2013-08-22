# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"
require "warden/mount_point"

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

        # Block size of the file system housing the container depot
        def container_depot_block_size
          @container_depot_block_size ||= self.class.container_depot_block_size
        end

        def before_create(request, response)
          super

          # Reset quota limits
          setquota(uid) if self.class.disk_quota_enabled
        end

        def do_limit_disk(request, response)
          # return directly if the disk quota is diabled
          return nil unless self.class.disk_quota_enabled

          # Use current limits as defaults
          repquota = self.class.repquota(uid)

          limits = {}
          limits[:block_soft] = repquota[uid][:quota][:block][:soft]
          limits[:block_hard] = repquota[uid][:quota][:block][:hard]
          limits[:inode_soft] = repquota[uid][:quota][:inode][:soft]
          limits[:inode_hard] = repquota[uid][:quota][:inode][:hard]

          to_blocks = lambda do |bytes|
            bytes = bytes.to_i + container_depot_block_size - 1
            bytes / container_depot_block_size
          end

          to_bytes = lambda do |blocks|
            blocks * container_depot_block_size
          end

          limits[:block_hard] = to_blocks.call(request.byte_limit) if request.byte_limit
          limits[:block_hard] = to_blocks.call(request.byte)       if request.byte
          limits[:block_soft] = to_blocks.call(request.byte_soft)  if request.byte_soft
          limits[:block_hard] = to_blocks.call(request.byte_hard)  if request.byte_hard

          limits[:block_hard] = request.block_limit.to_i if request.block_limit
          limits[:block_hard] = request.block.to_i       if request.block
          limits[:block_soft] = request.block_soft.to_i  if request.block_soft
          limits[:block_hard] = request.block_hard.to_i  if request.block_hard

          limits[:inode_hard] = request.inode_limit.to_i if request.inode_limit
          limits[:inode_hard] = request.inode.to_i       if request.inode
          limits[:inode_soft] = request.inode_soft.to_i  if request.inode_soft
          limits[:inode_hard] = request.inode_hard.to_i  if request.inode_hard

          unless limits.empty?
            setquota(uid, limits)
          end

          # Return current limits
          repquota = self.class.repquota(uid)

          response.byte_limit  = to_bytes.call(repquota[uid][:quota][:block][:hard])
          response.byte        = to_bytes.call(repquota[uid][:quota][:block][:hard])
          response.byte_soft   = to_bytes.call(repquota[uid][:quota][:block][:soft])
          response.byte_hard   = to_bytes.call(repquota[uid][:quota][:block][:hard])

          response.block_limit = repquota[uid][:quota][:block][:hard]
          response.block       = repquota[uid][:quota][:block][:hard]
          response.block_soft  = repquota[uid][:quota][:block][:soft]
          response.block_hard  = repquota[uid][:quota][:block][:hard]

          response.inode_limit = repquota[uid][:quota][:inode][:hard]
          response.inode       = repquota[uid][:quota][:inode][:hard]
          response.inode_soft  = repquota[uid][:quota][:inode][:soft]
          response.inode_hard  = repquota[uid][:quota][:inode][:hard]

          nil
        end

        def do_info(request, response)
          super(request, response)

          begin
            # return nil directly if the disk quota is disabled
            return nil unless self.class.disk_quota_enabled

            usage = self.class.repquota(uid)[uid][:usage]

            stats = {
              :inodes_used => usage[:inode],
              :bytes_used  => usage[:bytes],
            }

            response.disk_stat = Protocol::InfoResponse::DiskStat.new(stats)
          rescue => e
            raise WardenError.new("Failed getting disk usage: #{e}")
          end

          nil
        end

        private

        def setquota(uid, limits = {})
          limits[:block_soft] ||= 0
          limits[:block_hard] ||= 0
          limits[:inode_soft] ||= 0
          limits[:inode_hard] ||= 0

          args  = ["setquota"]
          args += ["-u", uid].map(&:to_s)
          args += [limits[:block_soft], limits[:block_hard]].map(&:to_s)
          args += [limits[:inode_soft], limits[:inode_hard]].map(&:to_s)
          args += [container_depot_mount_point_path]
          sh *args
        end

        module ClassMethods

          include Spawn

          # switch to enable/disable disk quota
          attr_accessor :disk_quota_enabled

          def container_depot_mount_point_path
            @container_depot_mount_point_path ||=
              Warden::MountPoint.new.for_path(container_depot_path)
          end

          # We're interested in the quota blocksize, which is hardcoded by the
          # Linux kernel and may be different from the filesystem blocksize.
          # See <sys/mount.h> for the accurate BLOCK_SIZE.
          def container_depot_block_size
            1024
          end

          def setup(config)
            super(config)

            self.disk_quota_enabled = config.server["quota"]["disk_quota_enabled"]
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
                  :bytes => 0,
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

              usage[uid][:usage][:bytes] = fields[1]
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
