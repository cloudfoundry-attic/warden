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

module Warden

  module Server

    class Drainer
      module State
        INACTIVE             = 0 # Drain not yet initiated
        START                = 1 # Drain initiated, closing accept socket
        WAIT_ACCEPTOR_CLOSED = 2 # Waiting for the accept socket to be closed
        ACCEPTOR_CLOSED      = 3 # Accept socket closed, notifying active conns
        DRAINING             = 4 # Accept socket closed, waiting for conns to finish
        DONE                 = 5 # Accept socket closed, no active conns
      end

      def initialize(server)
        @server = server
        @connections = Set.new
        @state = State::INACTIVE
        @on_complete_callbacks = []
      end

      def drain
        return if @state != State::INACTIVE

        logger.info("Drain initiated")

        @state = State::START

        run_machine
      end

      def register_connection(conn)
        logger.debug("Connection registered: #{conn}")

        @connections.add(conn)
        run_machine
      end

      def unregister_connection(conn)
        logger.debug("Connection unregistered: #{conn}")

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
      network_start_address = Network::Address.new(config.network["pool_start_address"])
      network_size = config.network["pool_size"]
      network_pool = Pool::Network.new(network_start_address, network_size)
      container_klass.network_pool = network_pool

      port_pool = Pool::Port.new
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
      setup_user
    end

    # Must be called after pools are setup
    def self.recover_containers
      max_job_id = 0

      Dir.glob(File.join(container_klass.container_depot_path, "*")) do |path|
        next unless File.exist?(container_klass.snapshot_path(path))

        c = container_klass.from_snapshot(path)
        logger.info("Recovered container from #{path}")
        logger.debug("Container resources: #{c.resources}")

        if c.resources.has_key?("ports")
          container_klass.port_pool.delete(*c.resources["ports"])
        end
        container_klass.uid_pool.delete(c.resources["uid"])
        container_klass.network_pool.delete(c.resources["network"])

        c.jobs.each do |job_id, job|
          max_job_id = job_id > max_job_id ? job_id : max_job_id
        end

        container_klass.registry[c.handle] = c
      end

      container_klass.job_id = max_job_id

      nil
    end

    def self.drained_sentinel_path
      File.join(config.server["container_depot_path"], "drained")
    end

    def self.write_drained_sentinel
      File.open(drained_sentinel_path, "w+") do |f|
        f.write(Time.now.to_i)
      end
    end

    def self.read_drained_sentinel
      sentinel = false

      if File.exist?(drained_sentinel_path)
        sentinel = true
        FileUtils.rm(drained_sentinel_path)
      end

      sentinel
    end

    def self.run!
      ::EM.epoll

      old_soft, old_hard = Process.getrlimit(:NOFILE)
      Process.setrlimit(Process::RLIMIT_NOFILE, 32768)
      new_soft, new_hard = Process.getrlimit(:NOFILE)
      logger.debug("rlimit_nofile: %d => %d" % [old_soft, new_soft])

      ::EM.run {
        f = Fiber.new do
          drained = read_drained_sentinel

          container_klass.setup(self.config, drained)

          ::EM.error_handler do |error|
            logger.log_exception(error)
          end

          if drained
            recover_containers
          end

          FileUtils.rm_f(unix_domain_path)
          server = ::EM.start_unix_domain_server(unix_domain_path, ClientConnection)

          @drainer = Drainer.new(server)
          @drainer.on_complete do
            Fiber.new do
              logger.info("Drain complete")
              # Serialize container state
              container_klass.registry.each { |_, c| c.write_snapshot }

              # Write out sentinel so we know to recover on next startup
              write_drained_sentinel

              EM.stop
            end.resume
          end
          Signal.trap("USR2") { @drainer.drain }

          # This is intentionally blocking. We do not want to start accepting
          # connections before permissions have been set on the socket.
          FileUtils.chmod(unix_domain_permissions, unix_domain_path)

          # Let the world know Warden is ready for action.
          logger.info("Listening on #{unix_domain_path}, and ready for action.")
        end

        f.resume
      }
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

        Server.drainer.register_connection(self)
      end

      def unbind
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
        logger.debug("Draining connection")

        @draining = true

        if PREEMPTIVELY_CLOSE_ON_DRAIN.include?(@current_request.class)
          logger.debug("Current request is #{@current_request.class}, closing connection")
          close
        else
          logger.debug("Current request is #{@current_request.class}, waiting for completion")
        end
      end

      def send_response(obj)
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

        logger.debug2(request)

        f = Fiber.new {
          begin
            @blocked = true
            @current_request = request
            process(request)

          ensure
            @current_request = nil
            @blocked = false

            if @draining
              logger.debug2("Finished processing request, closing")
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
        send_error e
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

      class Request < Array

        def require_arguments
          unless yield(size)
            raise WardenError.new("invalid number of arguments")
          end
        end
      end
    end
  end
end
