require "warden/errors"
require "warden/container/base"
require "tempfile"
require "socket"

module Warden

  module Container

    class Insecure < Base

      def self.setup(config={})
        super

        # noop
      end

      def do_create(request, response)
        sh File.join(root_path, "create.sh"), container_path
        debug "insecure container created"
      end

      def do_stop(request, response)
        sh File.join(container_path, "stop.sh")
        debug "insecure container stopped"
      end

      def do_destroy(request, response)
        sh File.join(root_path, "destroy.sh"), container_path
        debug "insecure container destroyed"
      end

      def create_job(request)
        job = Job.new(self)

        child = DeferredChild.new(File.join(container_path, "run.sh"), :input => request.script)

        child.callback do
          job.resume [child.exit_status, child.stdout, child.stderr]
        end

        child.errback do |err|
          job.resume [nil, nil, nil]
        end

        job
      end

      def do_net_in(request, response)
        host_port = self.class.port_pool.acquire

        # Ignore the container port, since there is nothing we can do
        container_port = host_port

        # Port may be re-used after this container has been destroyed
        on(:after_destroy) {
          self.class.port_pool.release(port)
        }

        response.host_port      = host_port
        response.container_port = container_port

        nil
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

        # Add option hash
        args << { :timeout => nil }

        sh *args
      end

      def container_relative_path(path)
        File.join(container_path, "root", path[1..-1])
      end
    end
  end
end
