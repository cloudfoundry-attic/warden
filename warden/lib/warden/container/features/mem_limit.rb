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
            @child = DeferredChild.new(oom_notifier_path, container.memory_cgroup_path)
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
          memory = memory_cgroup_file_contents('memory.usage_in_bytes')
          memory_limit = memory_cgroup_file_contents('memory.limit_in_bytes')
          swap = memory_cgroup_file_contents('memory.memsw.usage_in_bytes')
          swap_limit = memory_cgroup_file_contents('memory.memsw.limit_in_bytes')
          stats = format_memory_stats(memory_cgroup_file_contents('memory.stat'))
          logger.warn("OOM happened for container with handle '#{handle}', memory usage: #{memory}, memory limit: #{memory_limit}, memory + swap usage: #{swap}, memory + swap limit: #{swap_limit}, #{stats}")

          events << "out of memory"

          oom_killer true

          if state == State::Active
            dispatch(Protocol::StopRequest.new)
          end
        end

        def format_memory_stats(memory_stats)
          memory_stats.gsub(' ', ': ').gsub("\n", ', ')
        end

        private :format_memory_stats

        def oom_killer(enable)
          File.open(File.join(memory_cgroup_path, "memory.oom_control"), 'w') do |f|
            f.write(enable ? '0' : '1')
          end
        end

        private :oom_killer

        def memory_cgroup_file_contents(filename)
          File.read(File.join(memory_cgroup_path, filename)).chomp
        rescue
          # memory.memsw.* files cannot be read when swapping is off
          '-'
        end

        private :memory_cgroup_file_contents

        def memory_cgroup_path
          cgroup_path(:memory)
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
          # Disable the oom killer before setting up the oom notifier.
          oom_killer false

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
          2.times do
            ["memory.limit_in_bytes", "memory.memsw.limit_in_bytes"].each do |path|
              File.open(File.join(memory_cgroup_path, path), 'w') do |f|
                f.write(limit_in_bytes.to_s)
              end
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

          limit_in_bytes = File.read(File.join(memory_cgroup_path, "memory.limit_in_bytes"))
          response.limit_in_bytes = limit_in_bytes.to_i

          nil
        end
      end
    end
  end
end
