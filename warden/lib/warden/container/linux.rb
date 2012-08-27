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

        def setup(config, drained = false)
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

          if !drained
            options = {
              :env => {
                "ALLOW_NETWORKS" => allow_networks.join(" "),
                "DENY_NETWORKS" => deny_networks.join(" "),
                "CONTAINER_ROOTFS_PATH" => container_rootfs_path,
                "CONTAINER_DEPOT_PATH" => container_depot_path,
                "CONTAINER_DEPOT_MOUNT_POINT_PATH" => container_depot_mount_point_path,
              },
              :timeout => nil
            }

            sh File.join(root_path, "setup.sh"), options
          end
        end
      end

      def env
        env = {
          "id" => handle,
          "network_host_ip" => host_ip.to_human,
          "network_container_ip" => container_ip.to_human,
          "network_netmask" => self.class.network_pool.netmask.to_human,
          "user_uid" => uid,
          "rootfs_path" => container_rootfs_path,
        }
        env
      end

      def do_create(request, response)
        options = {
          :env => env,
          :timeout => nil
        }

        sh File.join(root_path, "create.sh"), container_path, options
        logger.debug("Container created")

        write_bind_mount_commands(request)
        logger.debug2("Wrote bind mount commands")

        write_etc_security_limits_conf
        logger.debug2("Wrote /etc/security/limits.conf")

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
        user = request.privileged ? "root" : "vcap"

        # -T: Never request a TTY
        # -F: Use configuration from <container_path>/ssh/ssh_config
        args = ["-T",
                "-F", File.join(container_path, "ssh", "ssh_config"),
                "#{user}@container"]
        args << { :input => request.script }

        spawn_job("ssh", *args)
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
        ssh_config_path = File.join(container_path, "ssh", "ssh_config")

        # Build arguments
        args  = ["rsync"]
        args += ["-e", "ssh -T -F #{ssh_config_path}"]
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

        File.open(File.join(container_path, "hook-parent-before-clone.sh"), "a") do |file|
          file.puts
          file.puts

          request.bind_mounts.each do |bind_mount|
            src_path = bind_mount.src_path
            dst_path = bind_mount.dst_path

            # Fix up destination path to be an absolute path inside the union
            dst_path = File.join(container_path, "union", dst_path[1..-1])

            mode = case bind_mount.mode
                   when Protocol::CreateRequest::BindMount::Mode::RO
                     "ro"
                   when Protocol::CreateRequest::BindMount::Mode::RW
                     "rw"
                   else
                     raise "Unknown mode"
                   end

            file.puts "mkdir -p #{dst_path}" % [dst_path]
            file.puts "mount -n --bind #{src_path} #{dst_path}"
            file.puts "mount -n --bind -o remount,#{mode} #{src_path} #{dst_path}"
          end
        end
      end

      def write_etc_security_limits_conf
        limits_conf_path = File.join(container_path, "rootfs", "etc", "security", "limits.conf")
        FileUtils.mkdir_p(File.dirname(limits_conf_path))
        File.open(limits_conf_path, "w") do |file|
          Server.container_limits_conf.each do |key, value|
            file.puts(["*", "-", key, value].join(" "))
          end
        end
      end
    end
  end
end
