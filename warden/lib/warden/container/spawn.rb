# coding: UTF-8

require "warden/errors"

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

        options = { :env => env, :timeout => 5.0, :max => 1024 * 1024 }.merge(options)

        p = DeferredChild.new(*(args + [options]))
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
          @env, @argv, @options = extract_process_spawn_arguments(*args)

          @child = Child.new(env, *(argv + [options]))

          @child.callback do
            set_deferred_success
          end

          @child.errback do |err|
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
          if !success?
            logger.warn("Exited with status %d (%.3fs): %s" % [exit_status.to_i, runtime, argv.inspect])
            logger.warn("Stdout: #{stdout}")
            logger.warn("Stderr: #{stderr}")
          else
            logger.debug("Exited with status %d (%.3fs): %s" % [exit_status.to_i, runtime, argv.inspect])
          end

          super
        end

        # Helper to inject log message
        def set_deferred_failure(err)
          logger.error("Error running #{argv.inspect}: #{err.message}")
          logger.warn("Stdout (maybe incomplete): #{stdout}")
          logger.warn("Stderr (maybe incomplete): #{stderr}")
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
