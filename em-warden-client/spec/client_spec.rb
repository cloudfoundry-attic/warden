require "spec_helper"
require "support/mock_warden_server"

describe EventMachine::Warden::Client do
  shared_examples_for "connection events" do
    let!(:server) { MockWardenServer.new(nil, socket_path) }

    it "should emit the 'connected' event upon connection completion" do
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

  shared_examples_for "connected" do
      let!(:request) { Warden::Protocol::EchoRequest.new(:message => "hello") }
      let!(:handler) { double }
      let(:server) { MockWardenServer.new(handler, socket_path) }
    it "should return non-error payloads" do
      expected_response = Warden::Protocol::EchoResponse.new(:message => "world")
      handler.should_receive(request.class.type_underscored).and_return(expected_response)
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
      expected_response = MockWardenServer::Error.new("test error")
      handler.should_receive(request.class.type_underscored).and_raise(expected_response)
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
      expected_response = Warden::Protocol::EchoResponse.new(:message => "world")
      handler.should_receive(request.class.type_underscored).twice.and_return(expected_response)

      em do
        server.start
        conn = server.create_connection
        conn.call(request)
        conn.call(request) { |r| EM.stop }
      end
    end

    it "should raise on disconnect" do
      handler.should_receive(request.class.type_underscored).and_return(nil)

      em do
        server.start

        conn = server.create_connection
        conn.call(request) do |r|
          expect do
            r.get
          end.to raise_error(EventMachine::Warden::Client::ConnectionError, /disconnected/i)

          EM.stop
        end

        # Close server side of the connection
        ::EM.add_timer(0.01) do
          server.connections.first.close_connection
        end
      end
    end
  end

  shared_examples_for "idle timer events" do
    let(:server) do
      handler = double
      handler.stub(request.class.type_underscored).and_return(response)

      server = MockWardenServer.new(handler, socket_path)
      server
    end

    let(:conn) { server.create_connection }

    let(:request) { Warden::Protocol::EchoRequest.new(:message => "hello") }

    let(:response) { Warden::Protocol::EchoResponse.new(:message => "world") }

    it "should setup an idle timer after connecting" do
      em do
        server.start

        conn.idle_timeout = 0.05

        # Check state after 2 * idle_timeout
        EM.add_timer(0.10) do
          conn.should_not be_connected
          EM.stop
        end
      end
    end

    it "should setup an idle timer after executing a request" do
      em do
        server.start

        conn.idle_timeout = 0.05

        conn.call(request) do |_|
          # Check state after 2 * idle_timeout
          EM.add_timer(0.10) do
            conn.should_not be_connected
            EM.stop
          end
        end
      end
    end

    it "should cancel the idle timer when busy" do
      em do
        server.start

        conn.idle_timeout = 0.05

        EM.add_periodic_timer(0.01) do
          conn.call(request)
        end

        # Check state after 2 * idle_timeout
        EM.add_timer(0.10) do
          conn.should be_connected
          EM.stop
        end
      end
    end
  end

end
