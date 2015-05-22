# coding: UTF-8

require "warden/container/base"
require "warden/errors"

require "socket"
require "tempfile"

module Warden

  module Container

    class Insecure < Base

      def self.setup(config)
        super

        # noop
      end

      def do_create(request, response)
        sh File.join(root_path, "create.sh"), container_path
        logger.debug("Container created")
      end

      def do_stop(request, response)
        args  = [File.join(container_path, "stop.sh")]
        args += ["-w", "0"] if request.kill

        sh *args

        nil
      end

      def do_destroy(request, response)
        sh File.join(container_path, "stop.sh"), "-w", "0", raise: false
        sh File.join(root_path, "destroy.sh"), container_path
        logger.debug("Container destroyed")
      end

      def create_job(request)
        spawn_job(
          { discard_output: request.discard_output,
            syslog_socket: Server.config.server["syslog_socket"],
            log_tag: request.log_tag,
          },
          File.join(container_path, "run.sh"),
          input: request.script,
          env: resource_limits(request),
        )
      end

      def do_net_in(request, response)
        host_port = self.class.port_pool.acquire

        # Ignore the container port, since there is nothing we can do
        container_port = host_port

        # Port may be re-used after this container has been destroyed
        @resources["ports"] << host_port
        @acquired["ports"] << host_port

        response.host_port      = host_port
        response.container_port = container_port

        nil
      end

      def acquire(opts = {})
        if !@resources.has_key?("ports")
          @resources["ports"] = []
          @acquired["ports"] = []
        else
          @acquired["ports"] = @resources["ports"].dup
        end

        super
      end

      def release
        if ports = @acquired.delete("ports")
          ports.each { |port| self.class.port_pool.release(port) }
        end

        super
      end

      def do_copy_in(request, response)
        src_path = request.src_path
        dst_path = request.dst_path

        perform_rsync(src_path, container_relative_path(dst_path))

        nil
      end

      def do_copy_out(request, response)
        src_path = request.src_path
        dst_path = request.dst_path

        perform_rsync(container_relative_path(src_path), dst_path)

        if request.owner
          sh "chown", "-R", request.owner, dst_path
        end

        nil
      end

      private

      def perform_rsync(src_path, dst_path)
        # Build arguments
        args  = ["rsync"]
        args += ["-r"]      # Recursive copy
        args += ["-p"]      # Preserve permissions
        args += ["--links"] # Preserve symlinks
        args += [src_path, dst_path]

        sh *args
      end

      def container_relative_path(path)
        File.join(container_path, "root", path[1..-1])
      end
    end
  end
end
