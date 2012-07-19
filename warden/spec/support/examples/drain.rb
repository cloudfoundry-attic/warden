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

  def drain
    Process.kill("USR2", @pid)
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
    t.run

    drain

    t.join
  end
end
