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

        def oomed
          logger.warn("OOM happened for #{handle}")

          events << 'oom'
          if state == State::Active
            dispatch(Protocol::StopRequest.new)
          end
        end

        def do_limit_memory(request, response)
          if request.limit_in_bytes
            begin

              # Need to set up the oom notifier before we set the memory limit
              # to avoid a race between when the limit is set and when the oom
              # notifier is registered.
              unless @oom_notifier
                @oom_notifier = OomNotifier.new(self)
                on(:after_stop) do
                  if @oom_notifier
                    @oom_notifier.kill
                    @oom_notifier = nil
                  end
                end
              end

              ["memory.limit_in_bytes", "memory.memsw.limit_in_bytes"].each do |path|
                File.open(File.join(cgroup_path(:memory), path), 'w') do |f|
                  f.write(request.limit_in_bytes.to_s)
                end
              end

            rescue => e
              raise WardenError.new("Failed setting memory limit: #{e}")
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
