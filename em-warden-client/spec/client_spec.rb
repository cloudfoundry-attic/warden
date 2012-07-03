require "spec_helper"
require "support/mock_warden_server"

describe EventMachine::Warden::Client do
  describe "events" do
    it "should emit the 'connected' event upon connection completion" do
      server = MockWardenServer.new
      received_connected = false

      em do
        server.start
        conn = server.create_connection
        conn.on(:connected) { received_connected = true }
        EM.stop
      end

      received_connected.should be_true
    end

    it "should emit the 'disconnected' event upon connection termination" do
      server = MockWardenServer.new
      received_disconnected = false

      em do
        server.start
        conn = server.create_connection
        conn.on(:disconnected) { received_disconnected = true }
        EM.stop
      end

      received_disconnected.should be_true
    end
  end

  describe "when connected" do
    it "should return non-error payloads" do
      request = Warden::Protocol::EchoRequest.new(:message => "hello")
      expected_response = Warden::Protocol::EchoResponse.new(:message => "world")

      handler = mock()
      handler.should_receive(request.type_underscored).and_return(expected_response)
      server = MockWardenServer.new(handler)
      actual_response = nil

      em do
        server.start
        conn = server.create_connection
        conn.call(request) do |r|
          actual_response = r.get
          EM.stop
        end
      end

      actual_response.should == expected_response
    end

    it "should raise error payloads" do
      request = Warden::Protocol::EchoRequest.new(:message => "hello world")
      expected_response = MockWardenServer::Error.new("test error")

      handler = mock()
      handler.should_receive(request.type_underscored).and_raise(expected_response)
      server = MockWardenServer.new(handler)

      em do
        server.start
        conn = server.create_connection
        conn.call(request) do |r|
          expect do
            r.get
          end.to raise_error(/test error/)
          EM.stop
        end
      end
    end

    it "should queue subsequent requests" do
      request = Warden::Protocol::EchoRequest.new(:message => "hello")
      expected_response = Warden::Protocol::EchoResponse.new(:message => "world")

      handler = mock()
      handler.should_receive(request.type_underscored).twice.and_return(expected_response)
      server = MockWardenServer.new(handler)

      em do
        server.start
        conn = server.create_connection
        conn.call(request)
        conn.call(request) { |r| EM.stop }
      end
    end
  end
end
