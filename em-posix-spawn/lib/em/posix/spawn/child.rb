require 'eventmachine'
require 'posix/spawn'

module EventMachine

  module POSIX

    module Spawn

      include ::POSIX::Spawn

      class Child

        include Spawn
        include Deferrable

        # Spawn a new process, write all input and read all output. Supports
        # the standard spawn interface as described in the POSIX::Spawn module
        # documentation:
        #
        #   new([env], command, [argv1, ...], [options])
        #
        # The following options are supported in addition to the standard
        # POSIX::Spawn options:
        #
        #   :input   => str      Write str to the new process's standard input.
        #   :timeout => int      Maximum number of seconds to allow the process
        #                        to execute before aborting with a TimeoutExceeded
        #                        exception.
        #   :max     => total    Maximum number of bytes of output to allow the
        #                        process to generate before aborting with a
        #                        MaximumOutputExceeded exception.
        #   :prepend_stdout => str Data to prepend to stdout
        #   :prepend_stderr => str Data to prepend to stderr
        #
        # Returns a new Child instance that is being executed. The object
        # includes the Deferrable module, and executes the success callback
        # when the process has exited, or the failure callback when the process
        # was killed because of exceeding the timeout, or exceeding the maximum
        # number of bytes to read from stdout and stderr combined. Once the
        # success callback is triggered, this objects's out, err and status
        # attributes are available. Clients can register callbacks to listen to
        # updates from out and err streams of the process.
        def initialize(*args)
          @env, @argv, options = extract_process_spawn_arguments(*args)
          @options = options.dup
          @input = @options.delete(:input)
          @timeout = @options.delete(:timeout)
          @max = @options.delete(:max)
          @discard_output = @options.delete(:discard_output)
          @prepend_stdout = @options.delete(:prepend_stdout) || ""
          @prepend_stderr = @options.delete(:prepend_stderr) || ""
          @options.delete(:chdir) if @options[:chdir].nil?

          exec!
        end

        # All data written to the child process's stdout stream as a String.
        attr_reader :out

        # All data written to the child process's stderr stream as a String.
        attr_reader :err

        # A Process::Status object with information on how the child exited.
        attr_reader :status

        # Total command execution time (wall-clock time)
        attr_reader :runtime

        attr_reader :pid

        # Determine if the process did exit with a zero exit status.
        def success?
          @status && @status.success?
        end

        # Determine if the process has already terminated.
        def terminated?
          !! @status
        end

        # Send the SIGTERM signal to the process.
        # Then send the SIGKILL signal to the process after the
        # specified timeout.
        def kill(timeout = 0)
          return false if terminated? || @sigkill_timer
          timeout ||= 0
          request_termination
          @sigkill_timer = Timer.new(timeout) {
            ::Process.kill('KILL', @pid) rescue nil
          }

          true
        end

        # Send the SIGTERM signal to the process.
        #
        # Returns the Process::Status object obtained by reaping the process.
        def request_termination
          @sigterm_timer.cancel if @sigterm_timer
          ::Process.kill('TERM', @pid) rescue nil
        end

        def add_streams_listener(&listener)
          [@cout.after_read(&listener), @cerr.after_read(&listener)]
        end

        class SignalHandler

          def self.setup!
            @instance ||= begin
                            new.tap do |instance|
                              instance.setup!
                            end
                          end
          end

          def self.teardown!
            if @instance
              @instance.teardown!
              @instance = nil
            end
          end

          def self.instance
            @instance
          end

          def initialize
            @pid_callback = {}
            @pid_to_process_status = {}
          end

          def setup!
            @pipe = ::IO.pipe
            @notifier = ::EM.watch @pipe[0], SignalNotifier, self
            @notifier.notify_readable = true

            @prev_handler = ::Signal.trap(:CHLD) do
              begin
                @pipe[1].write_nonblock("x")
              rescue IO::WaitWritable
              end

              @prev_handler.call unless @prev_handler == 'SYSTEM_DEFAULT'
            end

            @prev_handler ||= lambda { |*_| ; }
          end

          def teardown!
            ::Signal.trap(:CHLD, @prev_handler)

            @notifier.detach if ::EM.reactor_running?
            @pipe[0].close rescue nil
            @pipe[1].close rescue nil
          end

          def pid_callback(pid, &blk)
            @pid_callback[pid] = blk
          end

          def pid_to_process_status(pid)
            @pid_to_process_status.delete(pid)
          end

          def signal
            # The SIGCHLD handler may not be called exactly once for every
            # child. I.e., multiple children exiting concurrently may trigger
            # only one SIGCHLD in the parent. Therefore, reap all processes
            # that can be reaped.
            while pid = ::Process.wait(-1, ::Process::WNOHANG)
              @pid_to_process_status[pid] = $?
              blk = @pid_callback.delete(pid)
              EM.next_tick(&blk) if blk
            end
          rescue ::Errno::ECHILD
          end

          class SignalNotifier < ::EM::Connection
            def initialize(handler)
              @handler = handler
            end

            def notify_readable
              begin
                @io.read_nonblock(65536)
              rescue IO::WaitReadable
              end

              @handler.signal
            end
          end
        end

        # Execute command, write input, and read output. This is called
        # immediately when a new instance of this object is initialized.
        def exec!
          # The signal handler MUST be installed before spawning a new process
          SignalHandler.setup!

          if RUBY_PLATFORM =~ /linux/i && @options.delete(:close_others)
            @options[:in] = :in
            @options[:out] = :out
            @options[:err] = :err

            ::Dir.glob("/proc/%d/fd/*" % Process.pid).map do |file|
              fd = File.basename(file).to_i

              if fd > 2
                @options[fd] = :close
              end
            end
          end

          @pid, stdin, stdout, stderr = popen4(@env, *(@argv + [@options]))
          @start = Time.now

          # Don't leak into processes spawned after us.
          [stdin, stdout, stderr].each { |io| io.close_on_exec = true }

          # watch fds
          @cin = EM.watch stdin, WritableStream, (@input || "").dup, "stdin"
          @cout = EM.watch stdout, ReadableStream, @prepend_stdout, "stdout", @discard_output
          @cerr = EM.watch stderr, ReadableStream, @prepend_stderr, "stderr", @discard_output

          # register events
          @cin.notify_writable = true
          @cout.notify_readable = true
          @cerr.notify_readable = true

          # keep track of open fds
          in_flight = [@cin, @cout, @cerr].compact
          in_flight.each { |io|
            # force binary encoding
            io.force_encoding

            # register finalize hook
            io.callback { in_flight.delete(io) }
          }

          failure = nil

          # keep track of max output
          max = @max
          if max && max > 0
            check_buffer_size = lambda { |listener, _|
              if !terminated? && !listener.closed?
                if @cout.buffer.size + @cerr.buffer.size > max
                  failure = MaximumOutputExceeded
                  in_flight.each(&:close)
                  in_flight.clear
                  request_termination
                end
              end
            }

            @cout.after_read(&check_buffer_size)
            @cerr.after_read(&check_buffer_size)
          end

          # request termination of process when it doesn't terminate
          # in time
          timeout = @timeout
          if timeout && timeout > 0
            @sigterm_timer = Timer.new(timeout) {
              failure = TimeoutExceeded
              in_flight.each(&:close)
              in_flight.clear
              request_termination
            }
          end

          # run block when pid is reaped
          SignalHandler.instance.pid_callback(@pid) {
            @sigterm_timer.cancel if @sigterm_timer
            @sigkill_timer.cancel if @sigkill_timer
            @runtime = Time.now - @start
            @status = SignalHandler.instance.pid_to_process_status(@pid)

            in_flight.each do |io|
              # Trigger final read to make sure buffer is drained
              if io.respond_to?(:notify_readable)
                io.notify_readable
              end

              io.close
            end

            in_flight.clear

            @out = @cout.buffer
            @err = @cerr.buffer

            if failure
              set_deferred_failure failure
            else
              set_deferred_success
            end
          }
        end

        class Stream < Connection

          include Deferrable

          attr_reader :buffer

          def initialize(buffer, name)
            @buffer = buffer
            @name = name
            @closed = false
          end

          def force_encoding
            if @buffer.respond_to?(:force_encoding)
              @io.set_encoding('BINARY', 'BINARY')
              @buffer.force_encoding('BINARY')
            end
          end

          def close
            return if closed?


            # NB: Defer detach to the next tick, because EventMachine blows up
            #     when a file descriptor is attached and detached in the same
            #     tick. This can happen when the child process dies in the same
            #     tick it started, and the `#waitpid` loop in the signal
            #     handler picks it up afterwards. The signal handler, in turn,
            #     queues the child's callback to the executed via
            #     `EM#next_tick`. If the blocks queued by `EM#next_tick` are
            #     executed after that, still in the same tick, the child's file
            #     descriptors can be detached in the same tick they were
            #     attached.
            EM.next_tick do
              # NB: The ordering here is important. If we're using epoll,
              #     detach() attempts to deregister the associated fd via
              #     EPOLL_CTL_DEL and marks the EventableDescriptor for
              #     deletion upon completion of the iteration of the event
              #     loop. However, if the fd was closed before calling
              #     detach(), epoll_ctl() will sometimes return EBADFD and fail
              #     to remove the fd. This can lead to epoll_wait() returning
              #     an event whose data pointer is invalid (since it was
              #     deleted in a prior iteration of the event loop).
              detach
              @io.close rescue nil
            end

            @closed = true
          end

          def closed?
            @closed
          end
        end

        class ReadableStream < Stream

          class Listener

            attr_reader :name

            def initialize(name, &block)
              @name = name
              @block = block
              @offset = 0
            end

            # Sends the part of the buffer that has not yet been sent.
            def call(buffer)
              return if @block.nil?

              to_call = @block
              to_call.call(self, slice_from_buffer(buffer))
            end

            # Sends the part of the buffer that has not yet been sent,
            # after closing the listener. After this, the listener
            # will not receive any more calls.
            def close(buffer = "")
              return if @block.nil?

              to_call, @block = @block, nil
              to_call.call(self, slice_from_buffer(buffer))
            end

            def closed?
              @block.nil?
            end

            private

            def slice_from_buffer(buffer)
              to_be_sent = buffer.slice(@offset..-1)
              to_be_sent ||= ""
              @offset = buffer.length
              to_be_sent
            end
          end

          # Maximum buffer size for reading
          BUFSIZE = (64 * 1024)

          def initialize(buffer, name, discard_output = false, &block)
            super(buffer, name, &block)
            @discard_output = discard_output
            @after_read = []
          end

          def close
            # Ensure that the listener receives the entire buffer if it
            # attaches to the process only just before the stream is closed.
            @after_read.each do |listener|
              listener.close(@buffer)
            end

            @after_read.clear

            super
          end

          def after_read(&block)
            if block
              listener = Listener.new(@name, &block)
              if @closed
                # If this stream is already closed, then close the listener in
                # the next Event Machine tick. This ensures that the listener
                # receives the entire buffer if it attaches to the process only
                # after its completion.
                EM.next_tick do
                  listener.close(@buffer)
                end
              elsif !@buffer.empty?
                # If this stream's buffer is non-empty, pass it to the listener
                # in the next tick to avoid having to wait for the next piece
                # of data to be read.
                EM.next_tick do
                  listener.call(@buffer)
                end
              end

              @after_read << listener
              listener
            end
          end

          def notify_readable
            # Close and detach are decoupled, check if this notification is
            # supposed to go through.
            return if closed?

            begin
              out = @io.read_nonblock(BUFSIZE)
              @buffer << out unless @discard_output
              @after_read.each { |listener| listener.call(@buffer) }
            rescue Errno::EAGAIN, Errno::EINTR
            rescue EOFError
              close
              set_deferred_success
            end
          end
        end

        class WritableStream < Stream

          def notify_writable
            # Close and detach are decoupled, check if this notification is
            # supposed to go through.
            return if closed?

            begin
              boom = nil
              size = @io.write_nonblock(@buffer)
              @buffer = @buffer[size, @buffer.size]
            rescue Errno::EPIPE => boom
            rescue Errno::EAGAIN, Errno::EINTR
            end
            if boom || @buffer.size == 0
              close
              set_deferred_success
            end
          end
        end
      end
    end
  end
end
