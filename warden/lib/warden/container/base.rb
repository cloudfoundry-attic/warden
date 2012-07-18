# coding: UTF-8

require "warden/event_emitter"
require "warden/logger"
require "warden/errors"
require "warden/container/spawn"
require "warden/util"

require "eventmachine"
require "set"
require "warden/protocol"

module Warden

  module Container

    module State
      class Base
        def self.to_s
          self.name.split("::").last.downcase
        end
      end

      # Container object created, but setup not performed
      class Born < Base; end

      # Container setup completed
      class Active < Base; end

      # Triggered by an error condition in the container (e.g. OOM) or
      # explicitly by the user. All processes have been killed but the
      # container exists for introspection. No new commands may be run.
      class Stopped < Base; end

      # All state associated with the container has been destroyed.
      class Destroyed < Base; end
    end

    class Base

      include EventEmitter
      include Spawn
      include Logger

      class << self

        attr_reader :root_path
        attr_reader :container_rootfs_path
        attr_reader :container_depot_path

        # Stores a map of handles to their respective container objects. Only
        # live containers are reachable through this map. Containers are only
        # added when they are succesfully started, and are immediately removed
        # when they are being destroyed.
        def registry
          @registry ||= {}
        end

        def reset!
          @registry = nil
        end

        # These attributes need to be set by some setup routine.
        attr_accessor :network_pool
        attr_accessor :port_pool
        attr_accessor :uid_pool

        # Called before the server starts.
        def setup(config = {})
          @root_path = File.join(Warden::Util.path("root"),
                                 self.name.split("::").last.downcase)

          @container_rootfs_path   = config["server"]["container_rootfs_path"]
          @container_rootfs_path ||= config["server"]["container_rootfs"]
          @container_rootfs_path ||= File.join(@root_path, "base", "rootfs")

          @container_depot_path   = config["server"]["container_depot_path"]
          @container_depot_path ||= config["server"]["container_depot"]
          @container_depot_path ||= File.join(@root_path, "instances")

          FileUtils.mkdir_p(@container_depot_path)
        end

        # Generates process-wide unique job IDs
        def generate_job_id
          @job_id ||= 0
          @job_id += 1
        end
      end

      attr_reader :resources
      attr_reader :connections
      attr_reader :jobs
      attr_reader :events
      attr_reader :limits
      attr_reader :state
      attr_accessor :grace_time

      def initialize
        @resources   = Hash.new { |h,k| raise WardenError.new("Unknown resource: #{k}") }
        @connections = ::Set.new
        @jobs        = {}
        @events      = Set.new
        @limits      = {}
        @state       = State::Born
        @grace_time  = Server.container_grace_time
      end

      def network
        @network ||= resources[:network]
      end

      def handle
        @handle ||= network.to_hex
      end

      def host_ip
        @host_ip ||= network + 1
      end

      def container_ip
        @container_ip ||= network + 2
      end

      def uid
        @uid ||= resources[:uid]
      end

      def cancel_grace_timer
        return unless @destroy_timer

        debug "grace timer: cancel"

        ::EM.cancel_timer(@destroy_timer)
        @destroy_timer = nil
      end

      def setup_grace_timer
        return if grace_time.nil?

        debug "grace timer: setup (%.3fs)" % grace_time

        @destroy_timer = ::EM.add_timer(grace_time) do
          debug "grace timer: fired"
          fire_grace_timer
        end
      end

      def fire_grace_timer
        f = Fiber.new do
          debug "grace timer: destroy"

          begin
            dispatch(Protocol::DestroyRequest.new)

          rescue WardenError => err
            # Ignore, destroying after grace time is a best effort
          end
        end

        f.resume
      end

      def register_connection(conn)
        cancel_grace_timer

        if connections.add?(conn)
          conn.on(:close) do
            connections.delete(conn)

            # Setup grace timer when this was the last connection to reference
            # this container, and it hasn't already been destroyed
            if connections.empty? && !has_state?(State::Destroyed)
              setup_grace_timer
            end
          end
        end
      end

      def root_path
        @root_path ||= self.class.root_path
      end

      # Path to the chroot used as the ro portion of the union mount
      def container_rootfs_path
        @container_rootfs_path ||= self.class.container_rootfs_path
      end

      # Path to the directory that will house all created containers
      def container_depot_path
        @container_depot_path ||= self.class.container_depot_path
      end

      def container_path
        @container_path ||= File.join(container_depot_path, handle)
      end

      def hook(name, request, response, &blk)
        if respond_to?(name)
          m = method(name)
          if m.arity == 2
            m.call(request, response, &blk)
          else
            m.call(&blk)
          end
        else
          blk.call(request, response) if blk
        end
      end

      def dispatch(request, &blk)
        klass_name = request.class.name.split("::").last
        klass_name = klass_name.gsub(/Request$/, "")
        klass_name = klass_name.gsub(/(.)([A-Z])/) { |m| "#{m[0]}_#{m[1]}" }
        klass_name = klass_name.downcase

        response = request.create_response

        before_method = "before_%s" % klass_name
        hook(before_method, request, response)
        emit(before_method.to_sym)

        around_method = "around_%s" % klass_name
        hook(around_method, request, response) do
          do_method = "do_%s" % klass_name
          send(do_method, request, response, &blk)
        end

        after_method = "after_%s" % klass_name
        emit(after_method.to_sym)
        hook(after_method, request, response)

        response
      end

      def method_missing(sym, *args, &blk)
        if args.first.kind_of?(Protocol::BaseRequest)
          dispatch(args.first, &blk)
        else
          super
        end
      end

      # Acquire resources required for every container instance.
      def acquire
        @acquired ||= {}

        unless @resources.has_key?(:network)
          network = self.class.network_pool.acquire
          unless network
            raise WardenError.new("Could not acquire network")
          end

          @acquired[:network] = network
          @resources[:network] = network
        end

        unless @resources.has_key?(:uid)
          uid = self.class.uid_pool.acquire
          unless uid
            raise WardenError.new("Could not acquire UID")
          end

          @acquired[:uid] = uid
          @resources[:uid] = uid
        end
      end

      # Release resources required for every container instance.
      def release
        @acquired ||= {}

        if network = @acquired.delete(:network)
          self.class.network_pool.release(network)
        end

        if uid = @acquired.delete(:uid)
          self.class.uid_pool.release(uid)
        end
      end

      def before_create(request, response)
        check_state_in(State::Born)

        begin
          acquire

          self.state = State::Active

        rescue
          release
          raise
        end
      end

      def after_create(request, response)
        # Clients should be able to look this container up
        self.class.registry[handle] = self

        # Pass handle back to client
        response.handle = handle
      end

      def around_create
        begin
          yield
        rescue WardenError
          begin
            dispatch(Protocol::DestroyRequest.new)
          rescue WardenError
            # Make sure that resources are released
            release

            # Ignore, raise original error
          end

          raise
        end
      end

      def do_create(request, response)
        raise WardenError.new("not implemented")
      end

      def before_stop
        check_state_in(State::Active)

        self.state = State::Stopped
      end

      def do_stop(request, response)
        raise WardenError.new("not implemented")
      end

      def before_destroy
        check_state_in(State::Active, State::Stopped)

        # Clients should no longer be able to look this container up
        self.class.registry.delete(handle)

        unless self.state == State::Stopped
          begin
            self.stop(Protocol::StopRequest.new)
          rescue WardenError
            # Ignore, stopping before destroy is a best effort
          end
        end

        self.state = State::Destroyed
      end

      def after_destroy
        release
      end

      def do_destroy(request, response)
        raise WardenError.new("not implemented")
      end

      def before_spawn
        check_state_in(State::Active)
      end

      def do_spawn(request, response)
        job = create_job(request)
        jobs[job.job_id] = job

        response.job_id = job.job_id
      end

      def do_link(request, response)
        job = jobs[request.job_id]

        unless job
          raise WardenError.new("no such job")
        end

        exit_status, stdout, stderr = job.yield

        response.exit_status = exit_status
        response.stdout = stdout
        response.stderr = stderr
      end

      def do_stream(request, response, &blk)
        job = jobs[request.job_id]

        unless job
          raise WardenError.new("no such job")
        end

        job.stream(&blk)
      end

      def do_run(request, response)
        spawn_request = Protocol::SpawnRequest.new \
          :handle => request.handle,
          :script => request.script,
          :privileged => request.privileged

        spawn_response = dispatch(spawn_request)

        link_request = Protocol::LinkRequest.new \
          :handle => handle,
          :job_id => spawn_response.job_id

        link_response = dispatch(link_request)

        response.exit_status = link_response.exit_status
        response.stdout = link_response.stdout
        response.stderr = link_response.stderr
      end

      def before_net_in
        check_state_in(State::Active)
      end

      def do_net_in(request, response)
        raise WardenError.new("not implemented")
      end

      def before_net_out
        check_state_in(State::Active)
      end

      def do_net_out(request, response)
        raise WardenError.new("not implemented")
      end

      def before_copy_in
        check_state_in(State::Active)
      end

      def do_copy_in(request, response)
        raise WardenError.new("not implemented")
      end

      def before_copy_out
        check_state_in(State::Active)
      end

      def do_copy_out(request, response)
        raise WardenError.new("not implemented")
      end

      def before_limit_memory
        check_state_in(State::Active, State::Stopped)
      end

      def do_limit_memory(request, response)
        raise WardenError.new("not implemented")
      end

      def before_limit_disk
        check_state_in(State::Active, State::Stopped)
      end

      def do_limit_disk(request, response)
        raise WardenError.new("not implemented")
      end

      def before_info
        check_state_in(State::Active, State::Stopped)
      end

      def do_info(request, response)
        response.state = self.state.to_s
        response.events = self.events.to_a
        response.host_ip = self.host_ip.to_human
        response.container_ip = self.container_ip.to_human

        nil
      end

      protected

      def state
        @state
      end

      def state=(state)
        @state = state
      end

      def has_state?(state)
        self.state == state
      end

      def check_state_in(*states)
        unless states.include?(self.state)
          states_str = states.map {|s| s.to_s }.join(', ')
          raise WardenError.new("Container state must be one of '#{states_str}', current state is '#{self.state}'")
        end
      end

      class Job

        include Logger

        attr_reader :container
        attr_reader :job_id

        def initialize(container, child)
          @container = container
          @job_id = container.class.generate_job_id
          @child = child

          @status = nil
          @yielded = []
        end

        def yield
          return @status if @status
          @yielded << Fiber.current
          Fiber.yield
        end

        def resume(status)
          @status = status
          @yielded.each { |f| f.resume(@status) }
        end

        def stream(&block)
          fiber = Fiber.current
          listeners = @child.add_streams_listener do |listener, data|
            fiber.resume(listener, data) if fiber.alive?
          end

          while !listeners.all?(&:closed?)
            listener, data = Fiber.yield
            block.call(listener.name, data) unless data.empty?
          end
        end
      end
    end
  end
end
