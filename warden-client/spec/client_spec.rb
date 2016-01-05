require "spec_helper"
require "support/mock_warden_server"

describe Warden::Client do

  include_context :mock_warden_server

  let(:client) do
    new_client
  end

  it "shouldn't be able to connect without a server" do
    expect do
      client.connect
    end.to raise_error Errno::ECONNREFUSED

    expect(client).to_not be_connected
  end

  describe "connecting" do
    context "when there is a port supplied" do
      let(:client) do
        new_client(true) # makes tcp client
      end
      it "should be able to connect with a server" do
        start_server(true) # makes tcp server

        expect do
          client.connect
        end.to_not raise_error

        expect(client).to be_connected
      end
    end

    context "when there is no port supplied" do
      it "should be able to connect with a server" do
        start_server

        expect do
          client.connect
        end.to_not raise_error

        expect(client).to be_connected
      end
    end
  end

  context "connection management" do

    # This is super-racy: the ivar is updated from the server thread
    def connection_count
      sleep 0.001
      @sessions.size
    end

    before(:each) do
      @sessions = {}
      start_server do |session, _|
        @sessions[session] = 1
      end
    end

    context "when connected" do

      before(:each) do
        client.connect
        expect(client).to be_connected
        expect(connection_count).to eq(1)
      end

      it "should not allow connecting" do
        expect do
          client.connect
        end.to raise_error RuntimeError

        # This should not affect the connection
        expect(client).to be_connected

        # This should not reconnect
        expect(connection_count).to eq(1)
      end

      it "should allow disconnecting" do
        client.disconnect
        expect(client).to_not be_connected

        # This should not reconnect
        expect(connection_count).to eq(1)
      end

      it "should allow reconnecting" do
        client.reconnect
        expect(client).to be_connected

        # This should have reconnected
        expect(connection_count).to eq(2)
      end
    end

    context "when disconnected" do

      before(:each) do
        expect(connection_count).to eq(0)
      end

      it "should not allow disconnecting" do
        expect do
          client.disconnect
        end.to raise_error RuntimeError

        # This should not affect the connection
        expect(client).to_not be_connected

        # This should not reconnect
        expect(connection_count).to eq(0)
      end

      it "should allow connecting" do
        client.connect
        expect(client).to be_connected

        # This should have connected
        expect(connection_count).to eq(1)
      end

      # While it is semantically impossible to reconnect when the client was
      # never connected to begin with, it IS possible.
      it "should allow reconnecting" do
        client.reconnect
        expect(client).to be_connected

        # This should have connected
        expect(connection_count).to eq(1)
      end
    end
  end

  context "when connected" do

    before(:each) do
      container = nil
      job_id = nil

      start_server do |session, request|
        next if request.nil?

        if request.class == Warden::Protocol::EchoRequest
          case request.message
            when "eof"
              session.close
            when "error"
              args = {:message => "error"}
              session.respond(Warden::Protocol::ErrorResponse.new(args))
            else
              args = {:message => request.message}
              session.respond(request.create_response(args))
          end
        elsif request.class == Warden::Protocol::CreateRequest
          raise 'Cannot create more than one container' unless container.nil?

          container = "test"
          args = {:handle => container}
          session.respond(Warden::Protocol::CreateResponse.new(args))
        elsif request.class == Warden::Protocol::SpawnRequest
          raise 'Unknown handle' unless request.handle == container
          raise 'Cannot spawn more than one job' unless job_id.nil?

          job_id = 1
          args = {:job_id => job_id}
          session.respond(Warden::Protocol::SpawnResponse.new(args))
        elsif request.class == Warden::Protocol::StreamRequest
          raise 'Unknown handle' unless request.handle == container
          raise 'Unknown job' unless request.job_id == job_id

          args = {:name => "stream", :data => "test"}
          session.respond(Warden::Protocol::StreamResponse.new(args))
          args = {:exit_status => 0}
          session.respond(Warden::Protocol::StreamResponse.new(args))
        else
          raise "Unknown request type: #{request.class}."
        end
      end

      client.connect
      expect(client).to be_connected
    end

    it "should raise EOFError on eof" do
      expect do
        client.echo(:message => "eof")
      end.to raise_error(::EOFError)

      # This should update the connection status
      expect(client).to_not be_connected
    end

    it "should raise Warden::Client::ServerError on error payloads" do
      expect do
        client.echo(:message => "error")
      end.to raise_error(Warden::Client::ServerError)

      # This should not affect the connection
      expect(client).to be_connected
    end

    it "should return decoded payload for non-error replies" do
      response = client.echo(:message => "hello")
      expect(response.message).to eq("hello")
    end

    it "should work when called with the old API" do
      response = client.call(["echo", "hello"])
      expect(response).to eq("hello")
    end

    it "should stream data" do
      handle = client.create.handle
      response = client.spawn(:handle => handle, :script => "echo test")

      called = false
      block = lambda do |response|
        raise "Block should not be called more than once." if called

        expect(response).to be_an_instance_of Warden::Protocol::StreamResponse
        expect(response.data).to eq("test")
        expect(response.name).to eq("stream")
        expect(response.exit_status).to be_nil

        called = true
      end

      request = Warden::Protocol::StreamRequest.new(:handle => handle,
                                                    :job_id => response.job_id)
      response = client.stream(request, &block)
      expect(response.data).to be_nil
      expect(response.name).to be_nil
      expect(response.exit_status).to eq(0)

      expect(called).to be true
    end
  end
end
