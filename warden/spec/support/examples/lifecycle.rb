# encoding: UTF-8

module Warden::Protocol
  shared_examples "lifecycle" do
    it "should allow to create a container" do
      response = client.create
      expect(response.handle).to_not be_nil
    end

    it "should allow to create a container with a custom handle" do
      response = client.create(:handle => "test_handle")
      expect(response.handle).to eq "test_handle"
    end

    it "should allow to create a container with a custom non-ASCII handle" do
      response = client.create(:handle => "\302\202")
      expect(response.handle).to eq "\302\202"
    end

    it "should allow to use a container created with a custom handle" do
      response = client.create(:handle => "test_handle")
      expect(response.handle).to eq "test_handle"

      info = client.info(:handle => "test_handle")
      expect(info).to_not be_nil
    end

    it "should not allow to recreate a container that already exists" do
      response = client.create(:handle => "test_handle")
      expect(response.handle).to eq "test_handle"
      expect do
        response = client.create(:handle => "test_handle")
      end.to raise_error(/container with handle: test_handle already exists/)
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

      let(:stream_client) { create_client }
      let(:link_client) { create_client }
      let(:stop_client) { create_client }

      before do
        @handle = client.create.handle

        response = client.spawn \
        :handle => handle,
          :script => "set -e; trap 'exit 37' SIGTERM; echo x; sleep 5s; echo y; exit 38;"

        @job_id = response.job_id

        # Make sure that the process is actually running inside the container
        stream_client.write(Warden::Protocol::StreamRequest.new(:handle => handle,
          :job_id => @job_id))
        response = stream_client.read
        expect(response.name).to eq "stdout"
        expect(response.data).to eq "x\n"
        expect(response.exit_status).to eq nil

        stream_client.disconnect
      end

      it "can run in the background" do
        link_client.write(Warden::Protocol::LinkRequest.new(:handle => handle,
          :job_id => @job_id))

        stop_client.stop(:handle => handle, :background => true)

        # Test that exit status is returned (because of SIGTERM)
        response = link_client.read
        expect(response.exit_status).to eq 37
      end

      it "can kill everything ungracefully" do
        link_client.write(
          LinkRequest.new(:handle => handle, :job_id => @job_id))

        stop_client.stop(:handle => handle, :kill => true)

        # Test that no exit status is returned (because of SIGKILL)
        response = link_client.read
        expect(response.exit_status).to eq 255
      end

      it "contains the container info" do
        link_client.write(
          LinkRequest.new(:handle => handle, :job_id => @job_id))

        stop_client.stop(:handle => handle, :kill => true)

        response = link_client.read
        expect(response.info).to be_kind_of(InfoResponse)
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

        expect do
          client.reconnect
          client.run(:handle => handle, :script => 'echo')
        end.to eventually_error_with(Warden::Client::ServerError, /unknown handle/, 10)
      end

      it "should not blow up when container was already destroyed" do
        client.destroy(:handle => handle)

        # Disconnect the client
        client.disconnect

        # Test that the container can no longer be referenced
        expect do
          client.reconnect
          result = client.run(:handle => handle, :script => "echo")
        end.to eventually_error_with(Warden::Client::ServerError, /unknown handle/, 10)
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
          expect(response.exit_status).to eq 0
        end.to_not raise_error

        # Wait for the original grace time to run out
        sleep 1.0

        # The new connection should have taken over ownership of this
        # container and canceled the original grace time
        expect do
          response = client.run(:handle => handle, :script => "echo")
          expect(response.exit_status).to eq 0
        end.to_not raise_error
      end
    end
  end
end
