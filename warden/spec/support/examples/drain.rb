require "thread"

shared_examples "drain" do
  it "should cause the warden to exit after all connections are closed" do
    drain

    20.times do
      break if !warden_running?
      sleep 0.05
    end

    warden_running?.should be_false
  end

  it "should break connections that are inactive" do
    handle = client.create.handle

    drain
    # HACK: Make sure drain is processed before attempting destroy
    sleep 0.1

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
    # HACK: Make sure drain is processed
    sleep 0.1

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

  it "should allow linking to jobs that have already exited" do
    exp_status = 2
    exp_stdout = "hello"

    h = client.create.handle
    spawn_resp = client.spawn(:handle => h, :script => "echo -n #{exp_stdout}; exit #{exp_status}")
    job_id = spawn_resp.job_id
    link_resp = client.link(:handle => h, :job_id => job_id)
    link_resp.exit_status.should == exp_status
    link_resp.stdout.should == exp_stdout

    drain_and_restart

    c = create_client
    link_resp = c.link(:handle => h, :job_id => job_id)
    link_resp.exit_status.should == exp_status
    link_resp.stdout.should == exp_stdout
  end

  it "should allow linking to jobs that exit after the the restart" do
    exp_status = 2
    exp_stdout = "012345"
    script = "for x in {0..5}; do echo -n $x; sleep 1; done; exit #{exp_status}"

    h = client.create.handle
    job_id = client.spawn(:handle => h, :script => script).job_id

    drain_and_restart

    c = create_client
    start = Time.now
    link_resp = c.link(:handle => h, :job_id => job_id)
    elapsed = Time.now - start
    link_resp.exit_status.should == exp_status
    link_resp.stdout.should == exp_stdout

    # Check command was still running
    elapsed.should be > 1
  end

  it "should allow streaming jobs that have already exited" do
    exp_status = 2
    exp_stdout = "hello"

    h = client.create.handle
    spawn_resp = client.spawn(:handle => h, :script => "echo -n #{exp_stdout}; exit #{exp_status}")
    job_id = spawn_resp.job_id
    link_resp = client.link(:handle => h, :job_id => job_id)
    link_resp.exit_status.should == exp_status
    link_resp.stdout.should == exp_stdout

    drain_and_restart

    c = create_client
    streams = read_streams(c, h, job_id)
    streams.size.should == 1
    streams["stdout"].should == exp_stdout
  end

  it "should allow streaming jobs that exit after the restart" do
    exp_status = 2
    exp_stdout = "012345"
    script = "for x in {0..5}; do echo -n $x; sleep 1; done; exit #{exp_status}"

    h = client.create.handle
    job_id = client.spawn(:handle => h, :script => script).job_id

    drain_and_restart

    c = create_client
    start = Time.now
    streams = read_streams(c, h, job_id)
    elapsed = Time.now - start
    streams.size.should == 1
    streams["stdout"].should == exp_stdout
    # Check command was still running
    elapsed.should be > 1
  end

  def drain
    Process.kill("USR2", @pid)
  end

  def drain_and_restart
    drain
    Process.waitpid(@pid)
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

  def warden_running?
    # After hook reaps exit status
    File.read("/proc/#{@pid}/status") =~ /zombie/
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
