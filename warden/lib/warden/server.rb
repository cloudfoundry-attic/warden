# coding: UTF-8

require "warden/config"
require "warden/container"
require "warden/errors"
require "warden/event_emitter"
require "warden/network"
require "warden/pool/network"
require "warden/pool/port"
require "warden/pool/uid"

require "eventmachine"
require "fiber"
require "fileutils"
require "set"
require "steno"
require "steno/core_ext"
require "warden/protocol"
require "warden/protocol/buffer"
require "pidfile"

module Warden

  module Server

    class Drainer
      class DrainNotifier < ::EM::Connection
        def initialize(drainer)
          @drainer = drainer
        end

        def notify_readable
          begin
            @io.read_nonblock(65536)
          rescue IO::WaitReadable
          end

          @drainer.drain
        end
      end

      module State
        INACTIVE             = 0 # Drain not yet initiated
        START                = 1 # Drain initiated, closing accept socket
        WAIT_ACCEPTOR_CLOSED = 2 # Waiting for the accept socket to be closed
        ACCEPTOR_CLOSED      = 3 # Accept socket closed, notifying active conns
        DRAINING             = 4 # Accept socket closed, waiting for conns to finish
        DONE                 = 5 # Accept socket closed, no active conns
      end

      def initialize(server, signal)
        @server = server
        @connections = Set.new
        @state = State::INACTIVE
        @on_complete_callbacks = []

        setup(signal)
      end

      # The signal handler writes to a pipe to make it work with EventMachine.
      # If a signal handler calls into EventMachine directly it may result in
      # recursive locking, crashing the process.
      def setup(signal)
        @pipe = IO.pipe
        @notifier = ::EM.watch(@pipe[0], DrainNotifier, self)
        @notifier.notify_readable = true

        @prev_handler = ::Signal.trap(signal) do
          begin
            @pipe[1].write_nonblock("x")
          rescue IO::WaitWritable
          end

          @prev_handler.call if @prev_handler.respond_to?(:call)
        end
      end

      def drain
        return if @state != State::INACTIVE

        logger.info("Drain initiated")

        @state = State::START

        run_machine
      end

      def register_connection(conn)
        logger.debug2("Connection registered: #{conn}")

        @connections.add(conn)
        run_machine
      end

      def unregister_connection(conn)
        logger.debug2("Connection unregistered: #{conn}")

        @connections.delete(conn)
        run_machine
      end

      def on_complete(&blk)
        @on_complete_callbacks << blk
        run_machine
      end

      private

      def run_machine
        loop do
          case @state
          when State::INACTIVE, State::WAIT_ACCEPTOR_CLOSED
            break

          when State::START
            # Stop accepting new connections. There is no
            # stop_unix_domain_server.
            ::EM.stop_tcp_server(@server)

            # The accept socket is closed at the end of the current tick.
            ::EM.next_tick do
              @state = State::ACCEPTOR_CLOSED
              run_machine
            end
            @state = State::WAIT_ACCEPTOR_CLOSED

          when State::ACCEPTOR_CLOSED
            # Place existing connections into a "drain" state. This terminates
            # linked jobs.
            @connections.each { |c| c.drain }
            @state = State::DRAINING

          when State::DRAINING
            if @connections.empty?
              @state = State::DONE
            else
              break
            end

          when State::DONE
            @on_complete_callbacks.each { |blk| blk.call }
            @on_complete_callbacks = []
            break

          else
            raise WardenError.new("Invalid state!")
          end
        end

        nil
      end
    end

    def self.config
      @config
    end

    def self.unix_domain_path
      config.server["unix_domain_path"]
    end

    def self.unix_domain_permissions
      config.server["unix_domain_permissions"]
    end

    def self.container_klass
      config.server["container_klass"]
    end

    def self.container_grace_time
      config.server["container_grace_time"]
    end

    def self.container_limits_conf
      config.server["container_limits_conf"]
    end

    def self.drainer
      @drainer
    end

    def self.setup_server
      # noop
    end

    def self.setup_logging
      steno_config = ::Steno::Config.to_config_hash(config.logging)
      steno_config[:context] = ::Steno::Context::FiberLocal.new
      ::Steno.init(Steno::Config.new(steno_config))
    end

    def self.setup_network
      network_pool = Pool::Network.new(config.network["pool_network"], :release_delay => config.network["release_delay"])
      container_klass.network_pool = network_pool
    end

    def self.setup_port
      port_start_port = config.port["pool_start_port"]
      port_size = config.port["pool_size"]
      port_pool = Pool::Port.new(port_start_port, port_size)
      container_klass.port_pool = port_pool
    end

    def self.setup_user
      uid_start_uid = config.user["pool_start_uid"]
      uid_size = config.user["pool_size"]
      uid_pool = Pool::Uid.new(uid_start_uid, uid_size)
      container_klass.uid_pool = uid_pool
    end

    def self.setup(config)
      @config = Config.new(config)

      setup_server
      setup_logging
      setup_network
      setup_port
      setup_user
    end

    # Must be called after pools are setup
    def self.recover_containers
      max_job_id = 0

      Dir.glob(File.join(container_klass.container_depot_path, "*")) do |path|
        if !File.exist?(container_klass.snapshot_path(path))
          logger.info("Destroying container without snapshot at: #{path}")
          system(File.join(container_klass.root_path, "destroy.sh"), path)
          next
        end

        if !container_klass.alive?(path)
          logger.info("Destroying dead container at: #{path}")
          system(File.join(container_klass.root_path, "destroy.sh"), path)
          next
        end

        begin
          c = container_klass.from_snapshot(path)
          c.setup_grace_timer

          logger.info("Recovered container at: #{path}", :resources => c.resources)

          c.jobs.each do |job_id, job|
            max_job_id = job_id > max_job_id ? job_id : max_job_id
          end

          container_klass.registry[c.handle] = c
        rescue WardenError => err
          logger.log_exception(err)

          logger.warn("Destroying unrecoverable container at: #{path}")
          system(File.join(container_klass.root_path, "destroy.sh"), path)
        end
      end

      container_klass.job_id = max_job_id

      nil
    end

    def self.run!
      ::EM.epoll

      old_soft, old_hard = Process.getrlimit(:NOFILE)
      Process.setrlimit(Process::RLIMIT_NOFILE, 32768)
      new_soft, new_hard = Process.getrlimit(:NOFILE)
      logger.debug2("rlimit_nofile: %d => %d" % [old_soft, new_soft])

      # Log configuration
      logger.info("Configuration", config.to_hash)

      ::EM.run {
        f = Fiber.new do
          container_klass.setup(self.config)

          ::EM.error_handler do |error|
            logger.log_exception(error)
          end

          recover_containers

          FileUtils.rm_f(unix_domain_path)
          server = ::EM.start_unix_domain_server(unix_domain_path, ClientConnection)
          ::EM.start_server("127.0.0.1",
                            config.health_check_server["port"],
                            HealthCheck)

          @drainer = Drainer.new(server, "USR2")
          @drainer.on_complete do
            Fiber.new do
              logger.info("Drain complete")

              # Serialize container state
              container_klass.registry.each { |_, c| c.write_snapshot }
              container_klass.registry.each { |_, c| c.jobs.each_value(&:kill) }

              EM.stop
            end.resume(nil)
          end

          # This is intentionally blocking. We do not want to start accepting
          # connections before permissions have been set on the socket.
          FileUtils.chmod(unix_domain_permissions, unix_domain_path)

          # Let the world know Warden is ready for action.
          logger.info("Listening on #{unix_domain_path}")

          if pidfile = config.server["pidfile"]
            logger.info("Writing pid #{Process.pid} to #{pidfile}")
            PidFile.new(piddir: File.dirname(pidfile), pidfile: File.basename(pidfile))
          end
        end

        f.resume
      }
    end

    class HealthCheck < EM::Connection
      def receive_data(data)
        send_data("HTTP/1.1 200 OK\r\n")
        close_connection_after_writing
      end
    end

    class ClientConnection < ::EM::Connection

      PREEMPTIVELY_CLOSE_ON_DRAIN = [NilClass, Protocol::StreamRequest,
                                     Protocol::LinkRequest, Protocol::RunRequest]
      CRLF = "\r\n"

      include EventEmitter

      def post_init
        @draining = false
        @current_request = nil
        @blocked = false
        @closing = false
        @requests = []
        @buffer = Protocol::Buffer.new
        @bound = true

        Server.drainer.register_connection(self)
        Server.container_klass.registry.each do |_, container|
          container.register_connection(self)
        end
      end

      def bound?
        @bound
      end

      def unbind
        @bound = false

        f = Fiber.new { emit(:close) }
        f.resume

        Server.drainer.unregister_connection(self)
      end

      def close
        close_connection_after_writing
        @closing = true
      end

      def closing?
        !! @closing
      end

      def drain
        logger.debug("Draining connection on: #{self}")

        @draining = true

        if PREEMPTIVELY_CLOSE_ON_DRAIN.include?(@current_request.class)
          logger.debug("Current request is #{@current_request.class}, closing connection on #{self}")
          close
        else
          logger.debug("Current request is #{@current_request.class}, waiting for completion on #{self}")
        end
      end

      def send_response(obj)
        logger.debug2(obj.inspect)

        data = obj.wrap.encode.to_s
        send_data data.length.to_s + "\r\n"
        send_data data + "\r\n"
      end

      def send_error(err)
        send_response Protocol::ErrorResponse.new(:message => err.message)
      end

      def receive_data(data)
        @buffer << data
        @buffer.each_request do |request|
          begin
            receive_request(request)
          rescue => e
            close_connection_after_writing
            logger.warn("Disconnected client after error")
            logger.log_exception(e)
          end
        end
      end

      def receive_request(req = nil)
        @requests << req if req

        # Don't start new request when old one hasn't finished, or the
        # connection is about to be closed.
        return if @blocked or @closing

        request = @requests.shift

        return if request.nil?

        logger.debug2(request.inspect)

        f = Fiber.new {
          begin
            @blocked = true
            @current_request = request
            process(request)

          ensure
            @current_request = nil
            @blocked = false

            if @draining
              logger.debug("Finished processing request, closing #{self}")
              close
            else
              # Resume processing the input buffer
              ::EM.next_tick { receive_request }
            end
          end
        }

        f.resume
      end

      def process(request)
        case request
        when Protocol::PingRequest
          response = request.create_response
          send_response(response)

        when Protocol::ListRequest
          response = request.create_response
          response.handles = Server.container_klass.registry.keys.map(&:to_s)
          send_response(response)

        when Protocol::EchoRequest
          response = request.create_response
          response.message = request.message
          send_response(response)

        when Protocol::CreateRequest
          container = Server.container_klass.new
          container.register_connection(self)
          response = container.dispatch(request)
          send_response(response)

        else
          if request.respond_to?(:handle)
            container = find_container(request.handle)
            process_container_request(request, container)
          else
            raise WardenError.new("Unknown request: #{request.class.name.split("::").last}")
          end
        end
      rescue WardenError => e
        send_error(e)
      rescue => e
        logger.log_exception(e)
        send_error(e)
      end

      def process_container_request(request, container)
        case request
        when Protocol::StopRequest
          if request.background
            # Dispatch request out of band when the `background` flag is set
            ::EM.next_tick do
              f = Fiber.new do
                # Ignore response
                container.dispatch(request)
              end

              f.resume
            end

            response = request.create_response
            send_response(response)
          else
            response = container.dispatch(request)
            send_response(response)
          end

        when Protocol::StreamRequest
          response = container.dispatch(request) do |name, data|
            break if !bound?

            response = request.create_response
            response.name = name
            response.data = data
            send_response(response)
          end

          # Terminate by sending exit status only.
          send_response(response)
        else
          response = container.dispatch(request)
          send_response(response)
        end
      end

      protected

      def find_container(handle)
        Server.container_klass.registry[handle].tap do |container|
          raise WardenError.new("unknown handle") if container.nil?

          # Let the container know that this connection references it
          container.register_connection(self)
        end
      end
    end
  end
end
