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

      def do_create
        sh "#{root_path}/create.sh #{container_path}"
        debug "insecure container created"
      end

      def do_stop
        sh "#{container_path}/stop.sh"
        debug "insecure container stopped"
      end

      def do_destroy
        sh "#{root_path}/destroy.sh #{container_path}"
        debug "insecure container destroyed"
      end

      def create_job(script, opts = {})
        job = Job.new(self)

        child = DeferredChild.new(File.join(container_path, "run.sh"), :input => script)

        child.callback do
          job.resume [child.exit_status, child.stdout, child.stderr]
        end

        child.errback do |err|
          job.resume [nil, nil, nil]
        end

        job
      end

      def do_net_in(container_port = nil)
        host_port = self.class.port_pool.acquire

        # Ignore the container port, since there is nothing we can do
        container_port = host_port

        # Port may be re-used after this container has been destroyed
        on(:after_destroy) {
          self.class.port_pool.release(port)
        }

        { :host_port => host_port, :container_port => container_port }
      end

      def do_copy_in(src_path, dst_path)
        perform_rsync(src_path, container_relative_path(dst_path))

        "ok"
      end

      def do_copy_out(src_path, dst_path, owner=nil)
        perform_rsync(container_relative_path(src_path), dst_path)

        if owner
          sh "chown -R #{owner} #{dst_path}"
        end

        "ok"
      end

      private

      def perform_rsync(src_path, dst_path)
        cmd = ["rsync",
               "-r",           # Recursive copy
               "-p",           # Preserve permissions
               "--links",      # Preserve symlinks
               src_path,
               dst_path].join(" ")
        sh(cmd, :timeout => nil)
      end

      def container_relative_path(path)
        File.join(container_path, 'root', path.slice(1, path.length - 1))
      end

    end
  end
end
