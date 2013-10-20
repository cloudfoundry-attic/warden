# coding: UTF-8

require "warden/errors"
require "warden/util"

require "em/deferrable"
require "em/posix/spawn"
require "fiber"
require "steno"
require "steno/core_ext"

module Warden

  module Container

    module Spawn

      def self.included(base)
        base.extend(self)
      end

      def sh(*args)
        options =
          if args[-1].respond_to?(:to_hash)
            args.pop.to_hash.dup
          else
            {}
          end

        skip_raise = options.delete(:raise) == false

        # All environment variables must be strings
        env = options.delete(:env) || {}
        env.keys.each do |k|
          env[k] = env[k].to_s
        end

        options = { :env => env, :timeout => nil, :max => 1024 * 1024 }.merge(options)

        p = DeferredChild.new(*(args + [options]))
        p.logger = logger
        p.run
        p.yield

      rescue WardenError => err
        if skip_raise
          nil
        else
          raise
        end
      end

      # Thin utility class around EM::POSIX::Spawn::Child. It instruments the
      # logger in case of error conditions. Also, it considers any non-zero
      # exit status as an error. In this case, it tries to log as much
      # information as possible and subsequently triggers the failure callback.

      class DeferredChild

        include ::EM::POSIX::Spawn
        include ::EM::Deferrable

        attr_reader :env
        attr_reader :argv
        attr_reader :options

        attr_accessor :logger

        def pid
          @child.pid
        end

        def stdout
          @child.out
        end

        def stderr
          @child.err
        end

        def status
          @child.status
        end

        def runtime
          @child.runtime
        end

        def success?
          @child.success?
        end

        def exit_status
          @child.status.exitstatus
        end

        def kill(signal = "KILL")
          Process.kill(signal, @child.pid)
        end

        def initialize(*args)
          # Close all non-default file descriptors before spawning the child
          args.unshift(Util.path("src/closefds/closefds"))

          @env, @argv, @options = extract_process_spawn_arguments(*args)
        end

        def run
          @child = Child.new(env, *(argv + [options]))

          @child.callback do
            set_deferred_success
          end

          @child.errback do |err|
            logger.warn("child.errback", err: err.inspect)
            if err == MaximumOutputExceeded
              err = WardenError.new("command exceeded maximum output")
            elsif err == TimeoutExceeded
              err = WardenError.new("command exceeded maximum runtime")
            else
              err = WardenError.new("unexpected error: #{err.inspect}")
            end

            set_deferred_failure(err)
          end
        end

        # Helper to inject log message
        def set_deferred_success
          message = "Exited with status %d (%.3fs): %s" % [exit_status.to_i, runtime, argv.inspect]
          data = { :stdout => stdout, :stderr => stderr }

          if !success?
            logger.warn(message, data)
          else
            logger.debug2(message, data)
          end

          super
        end

        # Helper to inject log message
        def set_deferred_failure(err)
          logger.error("Error running #{argv.inspect}: #{err.message}", :stdout => stdout, :stderr => stderr)
          super
        end

        def add_streams_listener(&listener)
          @child.add_streams_listener(&listener)
        end

        def yield
          f = Fiber.current

          callback do
            if success?
              f.resume(:ok, stdout)
            else
              f.resume(:err, WardenError.new("command exited with failure"))
            end
          end

          errback do |err|
            f.resume(:err, err)
          end

          status, result = Fiber.yield

          raise result if status == :err

          result
        end
      end
    end
  end
end
