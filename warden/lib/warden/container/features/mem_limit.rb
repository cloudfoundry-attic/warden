# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"
require "warden/util"

module Warden

  module Container

    module Features

      module MemLimit

        class OomNotifier

          include Spawn

          attr_reader :container

          def initialize(container)
            @container = container

            oom_notifier_path = Warden::Util.path("src/oom/oom")
            @child = DeferredChild.new(oom_notifier_path, container.cgroup_path(:memory))
            @child.logger = logger
            @child.run
            @child_exited = false

            # Zero exit status means a process OOMed, non-zero means an error occurred
            @child.callback do
              @child_exited = true

              if @child.success?
                Fiber.new do
                  container.oomed
                end.resume
              end
            end

            # Don't care about errback, nothing we can do
          end

          def kill
            return if @child_exited

            @child.callback do
              @child_exited = true
            end

            logger.debug("Killing oom-notifier process")

            # em-posix-spawn reaps the exit status for us, so no waitpid needed
            # here.
            @child.kill
          end
        end

        def restore
          super

          if @resources.has_key?("limit_memory")
            limit_memory(@resources["limit_memory"])
          end
        end

        def oomed
          logger.warn("OOM happened for #{handle}")

          events << "out of memory"
          if state == State::Active
            dispatch(Protocol::StopRequest.new)
          end
        end

        def start_oom_notifier_if_needed
          unless @oom_notifier
            @oom_notifier = OomNotifier.new(self)

            on(:after_stop) do
              if @oom_notifier
                @oom_notifier.kill
                @oom_notifier = nil
              end
            end
          end
        end

        private :start_oom_notifier_if_needed

        def limit_memory(limit_in_bytes)
          # Need to set up the oom notifier before we set the memory
          # limit to avoid a race between when the limit is set and
          # when the oom notifier is registered.
          start_oom_notifier_if_needed

          # The memory limit may be increased or decreased. The fields that are
          # set have the following invariant:
          #
          #   memory.limit_in_bytes <= memory.memsw.limit_in_bytes
          #
          # If the limit is increased and memory.limit_in_bytes is set first,
          # the invariant may not hold. Similarly, if the limit is decreased
          # and memory.memsw.limit_in_bytes is set first, the invariant may not
          # hold. However, one of the two fields will always be set
          # successfully. To mitigate this, both limits are written twice.
          memory_limit_path = "memory.limit_in_bytes"
          memorysw_limit_path = "memory.memsw.limit_in_bytes"
          current_memory_limit = File.read(File.open(File.join(cgroup_path(:memory), memory_limit_path), 'r')).to_i

          increasing = current_memory_limit < limit_in_bytes

          paths = [memory_limit_path, memorysw_limit_path]
          paths.reverse! if increasing

          paths.each do |path|
            File.open(File.join(cgroup_path(:memory), path), 'w') do |f|
              f.write(limit_in_bytes.to_s)
            end
          end
        end

        private :limit_memory

        def do_limit_memory(request, response)
          if request.limit_in_bytes
            begin
              limit_memory(request.limit_in_bytes)
            rescue => e
              raise WardenError.new("Failed setting memory limit: #{e}")
            else
              @resources["limit_memory"] = request.limit_in_bytes
            end
          end

          limit_in_bytes = File.read(File.join(cgroup_path(:memory), "memory.limit_in_bytes"))
          response.limit_in_bytes = limit_in_bytes.to_i

          nil
        end
      end
    end
  end
end
