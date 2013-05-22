# coding: UTF-8

require "warden/container/base"
require "warden/container/features/cgroup"
require "warden/container/features/mem_limit"
require "warden/container/features/net"
require "warden/container/features/quota"
require "warden/errors"

require "shellwords"

module Warden

  module Container

    class Linux < Base

      include Features::Cgroup
      include Features::Net
      include Features::MemLimit
      include Features::Quota

      class << self

        attr_reader :bind_mount_script_template

        def setup(config)
          unless Process.uid == 0
            raise WardenError.new("linux containers require root privileges")
          end

          super(config)

          unless File.directory?(container_rootfs_path)
            raise WardenError.new("container_rootfs_path does not exist #{container_rootfs_path}")
          end

          unless File.directory?(container_depot_path)
            raise WardenError.new("container_depot_path does not exist #{container_depot_path}")
          end

          options = {
            :env => {
              "POOL_NETWORK" => config.network["pool_network"],
              "ALLOW_NETWORKS" => allow_networks.join(" "),
              "DENY_NETWORKS" => deny_networks.join(" "),
              "CONTAINER_ROOTFS_PATH" => container_rootfs_path,
              "CONTAINER_DEPOT_PATH" => container_depot_path,
              "CONTAINER_DEPOT_MOUNT_POINT_PATH" => container_depot_mount_point_path,
              "DISK_QUOTA_ENABLED" => disk_quota_enabled.to_s,
            },
            :timeout => nil
          }

          sh File.join(root_path, "setup.sh"), options
        end

        def alive?(path)
          socket_path = File.join(path, "run", "wshd.sock")

          begin
            socket = UNIXSocket.new(socket_path)
          rescue Errno::ECONNREFUSED
            # wshd is not running
            return false
          rescue Errno::ENOENT
            # unix socket is missing
            return false
          else
            socket.close
          end

          true
        end
      end

      def env
        env = {
          "id" => container_id,
          "network_host_ip" => host_ip.to_human,
          "network_container_ip" => container_ip.to_human,
          "network_netmask" => self.class.network_pool.pooled_netmask.to_human,
          "user_uid" => uid,
          "rootfs_path" => container_rootfs_path,
        }
        env
      end

      def do_create(request, response)
        options = {
          :env => env.dup,
          :timeout => nil
        }

        if request.rootfs
          unless Dir.exist? request.rootfs
            raise WardenError.new("rootfs #{request.rootfs} not found")
          end

          options[:env]["rootfs_path"] = request.rootfs
        end

        sh File.join(root_path, "create.sh"), container_path, options
        logger.debug("Container created")

        write_bind_mount_commands(request)
        logger.debug2("Wrote bind mount commands")

        sh File.join(container_path, "start.sh"), options
        logger.debug("Container started")

        nil
      end

      def do_stop(request, response)
        args  = [File.join(container_path, "stop.sh")]
        args += ["-w", "0"] if request.kill

        # Add option hash
        args << { :timeout => nil }

        sh *args

        nil
      end

      def do_destroy(request, response)
        sh File.join(root_path, "destroy.sh"), container_path, :timeout => nil
        logger.debug("Container destroyed")

        nil
      end

      def create_job(request)
        wsh_path = File.join(bin_path, "wsh")
        socket_path = File.join(container_path, "run", "wshd.sock")
        user = request.privileged ? "root" : "vcap"

        # Build arguments
        args  = [wsh_path]
        args += ["--socket", socket_path]
        args += ["--user", user]
        args += ["/bin/bash"]

        options = {
          :input => request.script,
          :env => resource_limits(request),
        }
        args << options

        spawn_job(*args)
      end

      def do_copy_in(request, response)
        src_path = request.src_path
        dst_path = request.dst_path

        perform_rsync(src_path, "vcap@container:#{dst_path}")

        nil
      end

      def do_copy_out(request, response)
        src_path = request.src_path
        dst_path = request.dst_path

        perform_rsync("vcap@container:#{src_path}", dst_path)

        if request.owner
          sh "chown", "-R", request.owner, dst_path
        end

        nil
      end

      private

      def perform_rsync(src_path, dst_path)
        wsh_path = File.join(bin_path, "wsh")
        socket_path = File.join(container_path, "run", "wshd.sock")

        # Build arguments
        args  = ["rsync"]
        args += ["-e", "#{wsh_path} --socket #{socket_path} --rsh"]
        args += ["-r"]      # Recursive copy
        args += ["-p"]      # Preserve permissions
        args += ["--links"] # Preserve symlinks
        args += [src_path, dst_path]

        # Add option hash
        args << { :timeout => nil }

        sh *args
      end

      def write_bind_mount_commands(request)
        return if request.bind_mounts.nil? || request.bind_mounts.empty?

        File.open(File.join(container_path, "lib", "hook-parent-before-clone.sh"), "a") do |file|
          file.puts
          file.puts

          request.bind_mounts.each do |bind_mount|
            src_path = bind_mount.src_path
            dst_path = bind_mount.dst_path

            # Check that the source path exists
            stat = File.stat(src_path) rescue nil
            if stat.nil?
              raise WardenError.new("Source path for bind mount does not exist: #{src_path}")
            end

            # Fix up destination path to be an absolute path inside the union
            dst_path = File.join(container_path, "mnt", dst_path[1..-1])

            mode = case bind_mount.mode
                   when Protocol::CreateRequest::BindMount::Mode::RO
                     "ro"
                   when Protocol::CreateRequest::BindMount::Mode::RW
                     "rw"
                   else
                     raise "Unknown mode"
                   end

            file.puts "mkdir -p #{dst_path}"
            file.puts "mount -n --bind #{src_path} #{dst_path}"
            file.puts "mount -n --bind -o remount,#{mode} #{src_path} #{dst_path}"
          end
        end
      end
    end
  end
end
