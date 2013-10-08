module Warden
  module Container
    class Base
      class Job
        include Spawn

        attr_reader :container
        attr_reader :job_id
        attr_reader :snapshot
        attr_reader :err

        attr_accessor :logger

        def initialize(container, job_id, snapshot = {})
          @container = container
          @job_id = job_id
          @snapshot = snapshot

          @yielded = []
        end

        def job_root_path
          container.job_path(job_id)
        end

        def cursors_path
          File.join(job_root_path, "cursors")
        end

        # Assumption: spawner cleans up after itself
        def stale?
          File.directory?(job_root_path) && Dir.glob(File.join(job_root_path, "*.sock")).empty?
        end

        def terminated?
          @snapshot.has_key?("status")
        end

        def run(discard_output = false)
          discard_output = @snapshot.fetch("discard_output", discard_output)

          @snapshot["discard_output"] = discard_output

          if !terminated?
            argv = [File.join(container.bin_path, "iomux-link"), "-w", cursors_path, job_root_path]

            @child = DeferredChild.new(*argv,
              :max => Server.config.server["job_output_limit"],
              :discard_output => discard_output)

            @child.logger = logger
            @child.run

            setup_child_handlers
          end
        end

        def yield
          if !terminated?
            @yielded << Fiber.current
            Fiber.yield
          else
            @snapshot["status"]
          end
        end

        def resume(status)
          @snapshot["status"] = status
          @container.write_snapshot
          @yielded.each { |f| f.resume(@snapshot["status"]) }
        end

        def stream(&block)
          # Handle the case where we are restarted after the job has completed.
          # In this situation there will be no child, hence no stream listeners.
          if terminated?
            exit_status, stdout, stderr = @snapshot["status"]
            block.call("stdout", stdout) unless stdout.empty?
            block.call("stderr", stderr) unless stderr.empty?
            return exit_status
          end

          fiber = Fiber.current
          listeners = @child.add_streams_listener do |listener, data|
            fiber.resume(listener, data) if fiber.alive?
          end

          while !listeners.all?(&:closed?)
            listener, data = Fiber.yield
            block.call(listener.name, data) unless data.empty?
          end

          # Wait until we have the exit status.
          exit_status, _, _ = self.yield
          exit_status
        end

        def cleanup(registry = {})
          # Clean up job root path
          EM.defer do
            FileUtils.rm_rf(job_root_path) if File.directory?(job_root_path)
          end

          # Clear job from registry
          registry.delete(job_id)
        end

        def to_snapshot
          # Drop stdout and stderr because we don't want to recover those after restart
          snapshot.dup.tap do |s|
            if s.has_key?("status")
              s["status"] = [s["status"].first, "", ""]
            end
          end
        end

        protected

        # An exit status of 255 from the child is ambiguous, and can
        # mean any one of the following:
        #
        # [1] The child exited with status 255.
        # [2] iomux linking failed with an internal error and exited with
        #     status of 255.
        # [3] The child exceeded the set output limit.
        #
        # Currently, we don't care about internal failures in iomux linking
        # and propogate the exit status as such. What we really need is
        # a clear way to differentiate exit statuses of iomux link from
        # the underlying child.
        def setup_child_handlers
          @child.callback do
            resume [@child.exit_status, @child.stdout, @child.stderr]
          end

          @child.errback do |err|
            @err = err
            # The errback is only called when an error occurred, such as when a
            # timeout happened, or the maximum output size has been exceeded.
            # Kill iomux-spawn if this happens.
            pid = @snapshot["iomux_spawn_pid"]
            begin
              Process.kill(:TERM, pid) if pid
            rescue Errno::ESRCH => e
              logger.warn("Cannot kill PID #{pid}: #{e}")
            rescue Errno::EPERM => e
              logger.warn("Cannot kill PID #{pid}: #{e}")
            end

            # Resume yielded fibers
            resume [255, @child.stdout, @child.stderr]
          end
        end
      end
    end
  end
end