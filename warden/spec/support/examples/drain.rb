require "thread"

shared_examples "drain" do
  def warden_running?
    # After hook reaps exit status
    File.read("/proc/#{@pid}/status") =~ /zombie/
  end

  it "should cause the warden to exit after all connections are closed" do
    Process.kill("USR2", @pid)

    20.times do
      break if !warden_running?
      sleep 0.05
    end

    warden_running?.should be_false
  end

  it "should break connections that are inactive" do
    handle = client.create.handle

    drain

    expect do
      client.destroy(:handle => handle)
    end.to raise_error
  end

  it "should break link requests" do
    check_request_broken do
      resp = client.spawn(:handle => handle, :script => "sleep 1000")
      client.link(:handle => handle, :job_id => resp.job_id)
    end
  end

  it "should break run requests" do
    check_request_broken do
      client.run(:handle => handle, :script => "sleep 1000")
    end
  end

  it "should break stream requests" do
    check_request_broken do
      resp = client.spawn(:handle => handle, :script => "sleep 1000")
      client.stream(:handle => handle, :job_id => resp.job_id)
    end
  end

  it "should snapshot all containers" do
    handle = client.create.handle
    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")

    drain

    File.exist?(snapshot_path).should be_true
  end

  it "should recreate existing containers" do
    active_handle = client.create.handle

    stopped_handle = client.create.handle
    client.stop(:handle => stopped_handle)

    drain_and_restart

    new_client = create_client

    [active_handle, stopped_handle].zip(["active", "stopped"]).each do |h, state|
      new_client.info(:handle => h).state.should == state
    end
  end

  # The only purpose for this test is to make sure we support an upgrade
  # path where the location of containers (and the path that is
  # synthesized from their ID) changes between restarts.
  it "should recreate existing containers whose paths have changed" do
    c = create_client
    handle = c.create.handle
    path = c.info(:handle => handle).container_path

    drain

    # Move container
    new_path = path + "__"
    FileUtils.mv(path, new_path)

    start_warden

    c = create_client
    c.info(:handle => handle).container_path.should == new_path
  end

  it "should not place existing containers networks back into the pool" do
    old_handle = client.create.handle

    drain_and_restart

    # Sort of a hack, relies on the fact that handles are encoded ips
    create_client.create.handle.should_not == old_handle
  end

  it "should not place existing containers ports back into the pool" do
    h = client.create.handle
    old_port = 10.times.reduce(0) { |_, _| client.net_in(:handle => h).host_port }

    drain_and_restart

    c = create_client
    h = c.create.handle
    c.net_in(:handle => h).host_port.should == (old_port + 1)
  end


  it "should not place existing containers uids back into the pool" do
    next if !have_uid_support

    client.create.handle
    h = client.create.handle
    old_uid = get_uid(client, h)

    drain_and_restart

    c = create_client
    h = c.create.handle
    get_uid(c, h).should == (old_uid + 1)
  end

  describe "jobs that stay alive over a restart" do
    let(:exp_status) { 2 }
    let(:exp_stdout) { "0123456789" }
    let(:discard_output) { false }
    let(:log_tag) { nil }
    let(:script) { "for x in {0..9}; do sleep 0.2; echo -n $x; done; exit #{exp_status}" }

    before do
      c = create_client
      @handle = c.create.handle
    end

    def spawn_job
      client.spawn(
        handle: @handle,
        script: script,
        discard_output: discard_output,
        log_tag: log_tag,
      ).job_id
    end

    it "should have one iomux-link when it's recovered" do
      job_id = spawn_job
      links_before_recover = `pgrep iomux-link | wc -l`
      drain_and_restart
      c = create_client
      links_after_recover = `pgrep iomux-link | wc -l`

      expect(links_before_recover).to eq(links_after_recover)
    end

    it "should allow linking" do
      job_id = spawn_job

      drain_and_restart

      c = create_client
      start = Time.now
      link_resp = c.link(:handle => @handle, :job_id => job_id)
      elapsed = Time.now - start
      link_resp.exit_status.should == exp_status
      link_resp.stdout.should == exp_stdout

      # Check command was still running
      elapsed.should be > 1
    end

    it "should allow streaming" do
      job_id = spawn_job

      drain_and_restart

      c = create_client
      start = Time.now
      streams = read_streams(c, @handle, job_id)
      elapsed = Time.now - start
      streams.size.should == 1
      streams["stdout"].should == exp_stdout

      # Check command was still running
      elapsed.should be > 1
    end

    context "and their output is discarded" do
      let(:discard_output) { true }

      it "does not allow streaming when it's recovered" do
        job_id = spawn_job

        c = create_client
        start = Time.now
        streams = read_streams(c, @handle, job_id)
        elapsed = Time.now - start

        streams.should be_empty

        # Check command was still running
        elapsed.should be > 1
      end
    end

    context "and their output is directed to syslog" do
      let(:log_tag) { "some_log_tag" }
      let(:script) { "for x in {0..30}; do sleep 1; echo $x; done; exit #{exp_status}" }

      let(:message_queue) { EventMachine::Queue.new }
      let(:socket_dir) { Dir.mktmpdir }
      let(:syslog_socket) { File.join(socket_dir, "log.sock") }

      class ClientConnection < EM::Connection
        def initialize(messages)
          @messages = messages
        end

        def receive_data(data)
          @messages.push data
        end
      end

      before do
        # for some reason warden has to be started after our
        # EM loop with the syslog server running, so stop the
        # existing one so we can start it manually
        stop_warden
        @client = nil
      end

      after { FileUtils.rm_rf(socket_dir) }

      def receive_logs(&blk)
        logs = []

        message_queue.pop do |log|
          logs << log

          message_queue.pop do |log|
            logs << log

            blk.call(logs)
          end
        end
      end

      it "continues redirecting to syslog when it's recovered" do
        em(timeout: 60) do
          EM.start_unix_domain_server(syslog_socket, ClientConnection, message_queue)

          start_warden

          job_id = spawn_job

          receive_logs do |logs|
            expect(logs.join).to include("warden.out.some_log_tag: 0")
            expect(logs.join).to include("warden.out.some_log_tag: 1")

            drain_and_restart

            receive_logs do |logs|
              expect(logs.join).to include("warden.out.some_log_tag: 2")
              expect(logs.join).to include("warden.out.some_log_tag: 3")

              system "pgrep iomux-link"


              EM.stop
            end
          end
        end
      end
    end
  end

  describe "jobs that exit before a restart" do
    before do
      c = create_client
      @handle = c.create.handle
      @job_id = client.spawn(:handle => @handle, :script => "sleep 0.2").job_id

      c = create_client
      c.write(Warden::Protocol::LinkRequest.new(:handle => @handle, :job_id => @job_id))

      sleep 0.1

      drain

      sleep 0.1

      start_warden
    end

    it "should not allow linking" do
      c = create_client
      expect do
        c.link(:handle => @handle, :job_id => @job_id)
      end.to raise_error(Warden::Client::ServerError, "no such job")
    end

    it "should not allow streaming" do
      c = create_client
      expect do
        read_streams(c, @handle, @job_id)
      end.to raise_error(Warden::Client::ServerError, "no such job")
    end
  end

  it "should not persist stdout/stderr over a restart" do
    c = create_client
    @handle = c.create.handle
    @job_id = client.spawn(:handle => @handle, :script => "echo hello; exit 2").job_id

    sleep 0.1

    drain_and_restart

    c = create_client
    link_response = c.link(:handle => @handle, :job_id => @job_id)
    link_response.stdout.should == ""
    link_response.stderr.should == ""
    link_response.exit_status.should == 2
  end

  def drain
    Process.kill("USR2", @pid)
    Process.waitpid(@pid)
  end

  def drain_and_restart
    drain
    start_warden
  end

  def read_streams(cli, handle, job_id)
    streams = Hash.new { |k, v| "" }

    cli.write(Warden::Protocol::StreamRequest.new(:handle => handle,
                                                  :job_id => job_id))

    loop do
      resp = cli.read
      break if resp.name.nil?

      streams[resp.name] += resp.data
    end

    streams
  end

  def get_uid(client, handle)
    run_resp = client.run(:handle => handle, :script => "id -u")
    run_resp.exit_status.should == 0
    Integer(run_resp.stdout.chomp)
  end

  def check_request_broken(&blk)
    handle = client.create.handle

    t = Thread.new do
      expect do
        blk.call
      end.to raise_error
    end

    # Force the request before the drain
    t.run if t.alive?

    drain

    t.join
  end
end
