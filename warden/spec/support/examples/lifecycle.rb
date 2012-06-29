shared_examples "lifecycle" do
  it "should allow to create a container" do
    response = client.create
    response.handle.should match(/^[0-9a-f]{8}$/i)
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

  describe "cleanup" do
    attr_reader :handle

    before do
      @handle = client.create.handle
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
