# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"
require "warden/event_emitter"
require "warden/util"

require "eventmachine"
require "fileutils"
require "set"
require "steno"
require "steno/core_ext"
require "warden/protocol"
require "yajl"

module Warden

  module Container

    module State
      def self.from_s(state)
        const_get(state.capitalize)
      end

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
        def setup(config)
          @root_path = File.join(Warden::Util.path("root"),
                                 self.name.split("::").last.downcase)

          @container_rootfs_path   = config.server["container_rootfs_path"]
          @container_rootfs_path ||= File.join(@root_path, "base", "rootfs")

          @container_depot_path   = config.server["container_depot_path"]
          @container_depot_path ||= File.join(@root_path, "instances")

          FileUtils.mkdir_p(@container_depot_path)
        end

        def job_id=(job_id)
          @job_id = job_id
        end

        # Generates process-wide unique job IDs
        def generate_job_id
          @job_id ||= 0
          @job_id += 1
        end

        def generate_container_id
          @container_id ||= begin
                              t = Time.now
                              t.tv_sec * 1_000_000 + t.tv_usec
                            end
          @container_id += 1

          # Explicit loop because we MUST have 11 characters.
          # This is required because we use the handle to name a network
          # interface for the container, this name has a 2 character prefix and
          # suffix, and has a maximum length of 15 characters (IFNAMSIZ).
          11.times.map do |i|
            ((@container_id >> (55 - (i + 1) * 5)) & 31).to_s(32)
          end.join
        end

        def snapshot_path(container_path)
          File.join(container_path, "snapshot.json")
        end

        def empty_snapshot
          { "events"     => [],
            "grace_time" => Server.container_grace_time,
            "jobs"       => {},
            "limits"     => {},
            "resources"  => {},
            "state"      => "born",
          }
        end

        def alive?(_)
          true
        end

        def from_snapshot(container_path)
          snapshot = Yajl::Parser.parse(File.read(snapshot_path(container_path)), :check_utf8 => false)
          snapshot["resources"]["network"] = Warden::Network::Address.new(snapshot["resources"]["network"])

          c = new(snapshot)
          c.container_path = container_path
          c.restore

          c
        end
      end

      attr_reader :resources
      attr_reader :connections
      attr_reader :jobs
      attr_reader :events
      attr_reader :limits
      attr_reader :state
      attr_reader :obituary
      attr_accessor :grace_time

      def initialize(snapshot = {}, jobs = {})
        snapshot = self.class.empty_snapshot.merge(snapshot)
        @resources   = {}
        @resources.update(snapshot["resources"])
        @acquired    = {}
        @connections = ::Set.new
        @jobs        = recover_jobs(snapshot["jobs"])
        @events      = Set.new(snapshot["events"])
        @limits      = snapshot["limits"]
        @state       = State.from_s(snapshot["state"])
        @grace_time  = snapshot["grace_time"]
      end

      def network
        @network ||= resources["network"]
      end

      def handle
        @resources["handle"]
      end

      def container_id
        @resources["container_id"]
      end

      def host_ip
        @host_ip ||= network + 1
      end

      def container_ip
        @container_ip ||= network + 2
      end

      def uid
        @uid ||= resources["uid"]
      end

      def cancel_grace_timer
        return unless @destroy_timer

        logger.debug2("Grace timer: cancel")

        ::EM.cancel_timer(@destroy_timer)
        @destroy_timer = nil
      end

      def setup_grace_timer
        return if grace_time.nil?

        logger.debug2("Grace timer: setup (fires in %.3fs)" % grace_time)

        @destroy_timer = ::EM.add_timer(grace_time) do
          fire_grace_timer
        end
      end

      def fire_grace_timer
        f = Fiber.new do
          logger.info("Grace timer fired, destroying container")

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
        @container_path ||= File.join(container_depot_path, container_id)
      end

      def container_path=(path)
        @container_path ||= path
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

      def bin_path
        File.join(container_path, "bin")
      end

      # Path to directory housing all job directories.
      def jobs_root_path
        @jobs_root_path ||= File.join(container_path, "jobs")
      end

      # Path to directory housing the control sockets for the job
      def job_path(job_id)
        File.join(jobs_root_path, job_id.to_s)
      end

      def snapshot_path
        self.class.snapshot_path(container_path)
      end

      def dispatch(request, &blk)
        klass_name = request.class.name.split("::").last
        klass_name = klass_name.gsub(/Request$/, "")
        klass_name = klass_name.gsub(/(.)([A-Z])/) { |m| "#{m[0]}_#{m[1]}" }
        klass_name = klass_name.downcase

        response = request.create_response

        t1 = Time.now

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

        t2 = Time.now

        logger.info("%s (took %.6f)" % [klass_name, t2 - t1],
                    :request => request.to_hash,
                    :response => response.to_hash)

        response
      end

      def delete_snapshot
        FileUtils.rm_f(snapshot_path)
      end

      def write_snapshot
        t1 = Time.now

        jobs_snapshot = {}
        jobs.each { |id, job| jobs_snapshot[id] = job.to_snapshot }

        snapshot = {
          "events"     => events.to_a,
          "jobs"       => jobs_snapshot,
          "limits"     => limits,
          "grace_time" => grace_time,
          "resources"  => resources,
          "state"      => state,
        }

        file = Tempfile.new("snapshot", File.join(container_path, "tmp"))
        file.write(Yajl::Encoder.encode(snapshot, :check_utf8 => false))
        file.close

        File.rename(file.path, snapshot_path)

        t2 = Time.now

        logger.debug("Wrote snapshot in %.6f" % [t2 - t1])

        nil
      end

      # Restore state from snapshot
      def restore
        acquire

        if @resources.has_key?("ports")
          self.class.port_pool.delete(*@resources["ports"])
        end

        if @resources.has_key?("uid")
          self.class.uid_pool.delete(@resources["uid"])
        end

        if @resources.has_key?("network")
          self.class.network_pool.delete(@resources["network"])
        end
      rescue WardenError
        release
        raise
      end

      # Acquire resources required for every container instance.
      def acquire(opts = {})
        if !@resources.has_key?("container_id")
          @resources["container_id"] = self.class.generate_container_id
        end

        if !@resources.has_key?("handle")
          if opts[:handle]
            if self.class.registry[opts[:handle]]
              raise WardenError.new("container with handle: #{opts[:handle]} already exists.")
            end

            @resources["handle"] = opts[:handle]
          else
            @resources["handle"] = @resources["container_id"]
          end
        end

        if @resources.has_key?("network")
          @acquired["network"] = network
        elsif opts[:network]
          # Translate to network address by network pool netmask
          container = Warden::Network::Address.new(opts[:network])
          network = container.network(self.class.network_pool.pooled_netmask)

          unless self.class.network_pool.fetch(network)
            raise WardenError.new("Could not acquire network: #{network.to_human}")
          end

          @acquired["network"] = network
          @resources["network"] = network
        else
          network = self.class.network_pool.acquire
          unless network
            raise WardenError.new("Could not acquire network")
          end

          @acquired["network"] = network
          @resources["network"] = network
        end

        if @resources.has_key?("uid")
          @acquired["uid"] = uid
        else
          uid = self.class.uid_pool.acquire
          unless uid
            raise WardenError.new("Could not acquire UID")
          end

          @acquired["uid"] = uid
          @resources["uid"] = uid
        end
      end

      # Release resources required for every container instance.
      def release
        @acquired ||= {}

        if network = @acquired.delete("network")
          self.class.network_pool.release(network)
        end

        if uid = @acquired.delete("uid")
          self.class.uid_pool.release(uid)
        end
      end

      def before_create(request, response)
        check_state_in(State::Born)

        begin
          acquire(:handle => request.handle, :network => request.network)

          if request.grace_time
            self.grace_time = request.grace_time
          end
        rescue
          release
          raise
        end
      end

      def after_create(request, response)
        self.state = State::Active

        # Clients should be able to look this container up
        self.class.registry[handle] = self

        write_snapshot

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

      def around_stop
        check_state_in(State::Active)

        self.state = State::Stopped

        begin
          delete_snapshot

          yield

          # Wait for all jobs to terminate (postcondition of stop)
          jobs.each_value(&:yield)
        ensure
          # Arguably the snapshot shouldn't be persisted when stop fails, but
          # failure of any essential command needs to be thought about more
          # before making an impromptu decision here.
          write_snapshot
        end
      end

      def do_stop(request, response)
        raise WardenError.new("not implemented")
      end

      def before_destroy
        check_state_in(State::Born, State::Active, State::Stopped)

        begin
          @obituary = dispatch(Protocol::InfoRequest.new(:handle => handle))
        rescue WardenError => e
          # Ignore, getting info before destroy is a best effort
          #
          # It's also likely that the creation of the container is what failed,
          # so there's no info to get anyway.
        end

        delete_snapshot

        self.class.registry.delete(handle)

        unless self.state == State::Stopped
          # Ignore, stopping before destroy is a best effort
          begin
            dispatch(Protocol::StopRequest.new)
          rescue WardenError => e
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

      def around_spawn
        check_state_in(State::Active)

        begin
          delete_snapshot
          yield
        ensure
          write_snapshot
        end
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

        job.cleanup(@jobs)

        response.info = container_info
        response.exit_status = exit_status
        response.stdout = stdout
        response.stderr = stderr
      end

      def do_stream(request, response, &blk)
        job = jobs[request.job_id]

        unless job
          raise WardenError.new("no such job")
        end

        response.info = container_info
        response.exit_status = job.stream(&blk)

        job.cleanup(@jobs)
      end

      def do_run(request, response)
        spawn_request = Protocol::SpawnRequest.new({
          :handle => request.handle,
          :script => request.script,
          :privileged => request.privileged,
          :rlimits => request.rlimits,
        })

        spawn_response = dispatch(spawn_request)

        link_request = Protocol::LinkRequest.new({
          :handle => handle,
          :job_id => spawn_response.job_id,
        })

        link_response = dispatch(link_request)

        response.info = container_info
        response.exit_status = link_response.exit_status
        response.stdout = link_response.stdout
        response.stderr = link_response.stderr
      end

      def around_net_in
        check_state_in(State::Active)

        begin
          delete_snapshot
          yield
        ensure
          write_snapshot
        end
      end

      def do_net_in(request, response)
        raise WardenError.new("not implemented")
      end

      def around_net_out
        check_state_in(State::Active)

        begin
          delete_snapshot
          yield
        ensure
          write_snapshot
        end
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
        check_state_in(State::Active, State::Stopped)
      end

      def do_copy_out(request, response)
        raise WardenError.new("not implemented")
      end

      def around_limit_memory
        check_state_in(State::Active, State::Stopped)

        begin
          delete_snapshot
          yield
        ensure
          write_snapshot
        end
      end

      def do_limit_memory(request, response)
        raise WardenError.new("not implemented")
      end

      def around_limit_disk
        check_state_in(State::Active, State::Stopped)

        begin
          delete_snapshot
          yield
        ensure
          write_snapshot
        end
      end

      def do_limit_disk(request, response)
        raise WardenError.new("not implemented")
      end

      def around_limit_bandwidth
        check_state_in(State::Active, State::Stopped)

        begin
          delete_snapshot
          yield
        ensure
          write_snapshot
        end
      end

      def do_limit_bandwidth(request, response)
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
        response.container_path = self.container_path
        response.job_ids = jobs.select do |job_id, job|
          !job.terminated?
        end.keys

        nil
      end

      protected

      def container_info
        obituary || dispatch(Warden::Protocol::InfoRequest.new(:handle => handle))
      end

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

      # Converts resource limits mentioned in a spawn/run request into a hash of
      # environment variables that can be passed to the job being spawned.
      def resource_limits(request)
        rlimits = Server.config.rlimits

        if request.rlimits
          request.rlimits.to_hash.each do |key, value|
            rlimits[key.to_s] = value
          end
        end

        rlimits_env = {}
        rlimits.each do |key, value|
          rlimits_env["RLIMIT_#{key.to_s.upcase}"] = value.to_s
        end

        rlimits_env
      end

      def spawn_job(*args)
        job_id = self.class.generate_job_id

        job_root = job_path(job_id)
        FileUtils.mkdir_p(job_root)

        f = Fiber.current

        spawn_path = File.join(bin_path, "iomux-spawn")
        spawner = DeferredChild.new(spawn_path, job_root, *args)
        spawner.logger = logger

        # When iomux-spawn starts up, there is a chance that it can fail before
        # it reaches the state where iomux-link can connect to it. We need to
        # handle this failure, as otherwise the client connection will be stuck
        # forever (the current fiber is never resumed). Therefore, within the
        # callbacks for the iomux-spawn job, we resume the yielded fiber
        # along with an indication of the failure in iomux-spawn.
        #
        # The flag: catch_spawner_failure ensures that the callbacks for
        # iomux-spawn perform their duty *only* when failures are detected
        # during iomux-spawn startup. Otherwise, these callbacks may be
        # triggered during the wrong time.
        catch_spawner_failure = true
        spawner.errback { f.resume(:no) if f.alive? && catch_spawner_failure }
        spawner.callback { f.resume(:no) if f.alive? && catch_spawner_failure }
        spawner.run

        # iomux-spawn indicates it is ready to receive connections by writing
        # the child's pid to stdout. Wait for that before attempting to
        # link. In the event that the spawner fails this code will still be
        # invoked, causing the linker to exit with status 255 (the desired
        # behavior).

        out = ""
        state = :wait_ready
        spawner.add_streams_listener do |_, data|
          out << data

          case state
          when :wait_ready
            state = :wait_child_active
            f.resume
          when :wait_child_active
            if out =~ /child active/
              state = :done
              f.resume
            end
          when :done
            # no-op
          end
        end

        # Wait for the spawner to be ready to receive connections
        spawner_alive = Fiber.yield
        raise WardenError.new("iomux-spawn failed")  if spawner_alive == :no

        # Wait for the spawned child to be continued
        job = Job.new(self, job_id, "iomux_spawn_pid" => spawner.pid)
        job.logger = logger
        job.run

        spawner_alive = Fiber.yield
        raise WardenError.new("iomux-spawn failed")  if spawner_alive == :no

        job
      ensure
        catch_spawner_failure = false
      end

      def recover_jobs(jobs_snapshot)
        jobs = {}

        jobs_snapshot.each do |job_id, job_snapshot|
          job = Job.new(self, Integer(job_id), job_snapshot)

          if !job.terminated? && job.stale?
            job.cleanup
            next
          end

          job.logger = logger
          job.run

          jobs[job.job_id] = job
        end

        jobs
      end

      def logger
        if @logger
          return @logger
        end

        if resources.has_key?("handle")
          @logger = self.class.logger.tag(:handle => resources["handle"])
          return @logger
        end

        self.class.logger
      end

      class Job

        include Spawn

        attr_reader :container
        attr_reader :job_id
        attr_reader :snapshot

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

        def run
          if !terminated?
            argv = [File.join(container.bin_path, "iomux-link"), "-w", cursors_path, job_root_path]

            @child = DeferredChild.new(*argv, :max => Server.config.server["job_output_limit"])
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
            # The errback is only called when an error occurred, such as when a
            # timeout happened, or the maximum output size has been exceeded.
            # Kill iomux-spawn if this happens.
            pid = @snapshot["iomux_spawn_pid"]
            begin
              Process.kill(:TERM, pid) if pid
            rescue Errno::EPERM => err
              logger.warn("Cannot kill PID #{pid}: #{err}")
            end

            # Resume yielded fibers
            resume [255, @child.stdout, @child.stderr]
          end
        end
      end
    end
  end
end
