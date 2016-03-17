require "thread"

shared_examples "drain" do
  include Helpers::Drain

  def warden_running?
    # After hook reaps exit status
    File.read("/proc/#{@pid}/status") =~ /zombie/
  end

  it "should cause the warden to exit after all connections are closed" do
    Process.kill("USR2", @pid)

    expect { warden_running? }.to eventually(be_falsey)
  end

  it "should break connections that are inactive" do
    handle = client.create.handle

    drain

    expect do
      client.destroy(:handle => handle)
    end.to raise_error Errno::EPIPE
  end

  it "should break link requests" do
    check_request_broken do |handle|
      resp = client.spawn(:handle => handle, :script => "sleep 1000")
      client.link(:handle => handle, :job_id => resp.job_id)
    end
  end

  it "should break run requests" do
    check_request_broken do |handle|
      client.run(:handle => handle, :script => "sleep 1000")
    end
  end

  it "should break stream requests" do
    check_request_broken do |handle|
      resp = client.spawn(:handle => handle, :script => "sleep 1000")

      stream_request = Warden::Protocol::StreamRequest.new
      stream_request.handle = handle
      stream_request.job_id = resp.job_id
      client.stream(stream_request)
    end
  end

  it "should snapshot all containers" do
    handle = client.create.handle
    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")

    drain

    expect(File.exist?(snapshot_path)).to be true
  end

  it "should recreate existing containers" do
    active_handle = client.create.handle

    stopped_handle = client.create.handle
    client.stop(:handle => stopped_handle)

    drain_and_restart

    new_client = create_client

    [active_handle, stopped_handle].zip(["active", "stopped"]).each do |h, state|
      expect(new_client.info(:handle => h).state).to eq state
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
    expect(c.info(:handle => handle).container_path).to eq new_path
  end

  it "should not place existing containers networks back into the pool" do
    old_handle = client.create.handle

    drain_and_restart

    # Sort of a hack, relies on the fact that handles are encoded ips
    expect(create_client.create.handle).to_not eq old_handle
  end

  it "should not place existing containers ports back into the pool" do
    h = client.create.handle
    old_port = 10.times.reduce(0) { |_, _| client.net_in(:handle => h).host_port }

    drain_and_restart

    c = create_client
    h = c.create.handle
    expect(c.net_in(:handle => h).host_port).to eq (old_port + 1)
  end


  it "should not place existing containers uids back into the pool" do
    next if !have_uid_support

    client.create.handle
    h = client.create.handle
    old_uid = get_uid(client, h)

    drain_and_restart

    c = create_client
    h = c.create.handle
    expect(get_uid(c, h)).to eq (old_uid + 1)
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
      expect(link_resp.exit_status).to eq exp_status
      expect(link_resp.stdout).to eq exp_stdout

      # Check command was still running
      expect(elapsed).to be > 1
    end

    it "should allow streaming" do
      job_id = spawn_job

      drain_and_restart

      c = create_client
      start = Time.now
      streams = read_streams(c, @handle, job_id)
      elapsed = Time.now - start
      expect(streams.size).to eq 1
      expect(streams["stdout"]).to eq exp_stdout

      # Check command was still running
      expect(elapsed).to be > 1
    end

    context "and their output is discarded" do
      let(:discard_output) { true }

      it "does not allow streaming when it's recovered" do
        job_id = spawn_job

        c = create_client
        start = Time.now
        streams = read_streams(c, @handle, job_id)
        elapsed = Time.now - start

        expect(streams).to be_empty

        # Check command was still running
        expect(elapsed).to be > 1
      end
    end

    context "and their output is directed to syslog" do
      let(:log_tag) { "some_log_tag" }
      let(:script) { "for x in {0..30}; do sleep 1; echo $x; done; exit #{exp_status}" }

      let(:socket_dir) { Dir.mktmpdir }
      let(:syslog_socket) { File.join(socket_dir, "log.sock") }

      class SocketServer
        def initialize(socket_path)
          @socket_server = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM, 0)
          @socket_server.bind(Socket.pack_sockaddr_un(socket_path))
        end

        def received_messages(num)
          messages = []
          num.times do
            messages << @socket_server.recvfrom(10*1024*1024)
          end
          messages.flatten
        end
      end

      before do
        # we need to start socket server before we start warden
        stop_warden
        @client = nil

        @socket_server = SocketServer.new(syslog_socket)
        start_warden
      end

      after { FileUtils.rm_rf(socket_dir) }

      it "continues redirecting to syslog when it's recovered" do
        spawn_job

        messages_received = @socket_server.received_messages(2).to_s

        expect(messages_received).to match /<14>.*warden.some_log_tag: 0/
        expect(messages_received).to match /<14>.*warden.some_log_tag: 1/

        drain_and_restart

        messages_received = @socket_server.received_messages(2).to_s

        expect(messages_received).to match /<14>.*warden.some_log_tag: 2/
        expect(messages_received).to match /<14>.*warden.some_log_tag: 3/
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

    sleep 1
    drain_and_restart

    c = create_client
    link_response = c.link(:handle => @handle, :job_id => @job_id)
    expect(link_response.stdout).to eq ""
    expect(link_response.stderr).to eq ""
    expect(link_response.exit_status).to eq 2
  end

  describe "grace time" do
    it "should destroy container after grace time on restart" do
      handle = client.create(:grace_time => 0).handle
      drain_and_restart

      expect do
        new_client = create_client
        new_client.info(:handle => handle)
      end.to eventually_error_with(Warden::Client::ServerError, /unknown handle/)
    end

    it "should cancel the timer when client reconnects" do
      handle = client.create(:grace_time => 1).handle
      drain_and_restart

      new_client = create_client
      sleep 1.1
      expect{ new_client.info(:handle => handle) }.to_not raise_error
    end
  end
end
