# coding: UTF-8

shared_examples "lifecycle" do
  it "should allow to create a container" do
    response = client.create
    response.handle.should_not be_nil
  end

  it "should allow to destroy a container" do
    handle = client.create.handle

    expect do
      client.destroy(:handle => handle)
    end.to_not raise_error
  end

  it "should not allow to destroy a container twice" do
    handle = client.create.handle

    expect do
      client.destroy(:handle => handle)
    end.to_not raise_error

    expect do
      client.destroy(:handle => handle)
    end.to raise_error(/unknown handle/i)
  end

  describe "stop" do
    attr_reader :handle
    attr_reader :job_id

    before do
      @handle = client.create.handle

      response = client.spawn \
        :handle => handle,
        :script => "trap 'sleep 0.5; exit 37;' SIGTERM; while true; do echo x; sleep 0.1; done"

      @job_id = response.job_id

      # Make sure that the process is actually running inside the container
      stream_client = create_client
      stream_client.write(Warden::Protocol::StreamRequest.new(:handle => handle,
                                                              :job_id => @job_id))
      stream_client.read
      stream_client.disconnect
    end

    it "can run in the background" do
      client.stop(:handle => handle, :background => true)

      t1 = Time.now
      response = client.link(:handle => handle, :job_id => job_id)
      t2 = Time.now

      # Test that linking still took some time after stop had already returned
      (t2 - t1).should be_within(0.25).of(0.5)
    end

    it "can kill everything ungracefully" do
      client.stop(:handle => handle, :kill => true)

      # Test that no exit status is returned (because of SIGKILL)
      response = client.link(:handle => handle, :job_id => job_id)
      response.exit_status.should == nil
    end
  end

  describe "cleanup" do
    attr_reader :handle

    before do
      @handle = client.create(:grace_time => 1).handle
    end

    it "should destroy unreferenced container" do
      # Disconnect the client
      client.disconnect

      # Let the grace time pass
      sleep 1.1

      # Test that the container can no longer be referenced
      expect do
        client.reconnect
        result = client.run(:handle => handle, :script => "echo")
      end.to raise_error(/unknown handle/i)
    end

    it "should not blow up when container was already destroyed" do
      client.destroy(:handle => handle)

      # Disconnect the client
      client.disconnect

      # Let the grace time pass
      sleep 1.1

      # Test that the container can no longer be referenced
      expect do
        client.reconnect
        result = client.run(:handle => handle, :script => "echo")
      end.to raise_error(/unknown handle/i)
    end

    it "should not destroy container when referenced by another client" do
      # Disconnect the client
      client.disconnect
      client.reconnect

      # Wait some time, but don't run out of grace time
      sleep 0.1

      # Test that the container can still be referenced
      expect do
        response = client.run(:handle => handle, :script => "echo")
        response.exit_status.should == 0
      end.to_not raise_error

      # Wait for the original grace time to run out
      sleep 1.0

      # The new connection should have taken over ownership of this
      # container and canceled the original grace time
      expect do
        response = client.run(:handle => handle, :script => "echo")
        response.exit_status.should == 0
      end.to_not raise_error
    end
  end
end
