require "spec_helper"
require "support/mock_warden_server"

describe EventMachine::Warden::FiberAwareClient do
  describe "#connected" do
    shared_examples_for "yield the calling fiber for connected" do
      it "should yield the calling fiber until connected" do
        server = MockWardenServer.new(nil, socket_path)

        em do
          server.start
          client = server.create_fiber_aware_client
          Fiber.new do
            client.connect
            client.connected?.should be_true
            EM.stop
          end.resume
        end
      end
    end

    context "when it has a file path" do
      let(:socket_path) { File.join(Dir.mktmpdir, "warden.sock") }
      it_should_behave_like "yield the calling fiber for connected"
    end

    context "when it has a network path" do
      let(:socket_path) { 'tcp://localhost:43248' }
      it_should_behave_like "yield the calling fiber for connected"
    end
  end

  describe "#disconnect" do
    shared_examples_for "yield the calling fiber for disconnect" do
      it "should yield the calling fiber until disconnected" do
        server = MockWardenServer.new(nil, socket_path)

        em do
          server.start
          client = server.create_fiber_aware_client
          Fiber.new do
            client.connect
            client.connected?.should be_true
            client.disconnect
            client.connected?.should be_false
            EM.stop
          end.resume
        end
      end
    end

    context "when it has a file path" do
      let(:socket_path) { File.join(Dir.mktmpdir, "warden.sock") }
      it_should_behave_like "yield the calling fiber for disconnect"
    end

    context "when it has a network path" do
      let(:socket_path) { 'tcp://localhost:43248' }
      it_should_behave_like "yield the calling fiber for disconnect"
    end
  end

  describe "#method_missing" do
    shared_examples_for "method missing payloads" do
      it "should return non-error payloads" do
        request = Warden::Protocol::EchoRequest.new(:message => "hello")
        expected_response = Warden::Protocol::EchoResponse.new(:message => "world")

        handler = double()
        handler.should_receive(request.class.type_underscored).and_return(expected_response)
        server = MockWardenServer.new(handler, socket_path)
        actual_response = nil

        em do
          server.start
          client = server.create_fiber_aware_client
          Fiber.new do
            client.connect
            actual_response = client.call(request)
            EM.stop
          end.resume
        end

        actual_response.should == expected_response
      end

      it "should raise error payloads" do
        request = Warden::Protocol::EchoRequest.new(:message => "hello world")
        expected_response = MockWardenServer::Error.new("test error")

        handler = double()
        handler.should_receive(request.class.type_underscored).and_raise(expected_response)
        server = MockWardenServer.new(handler, socket_path)

        em do
          server.start
          client = server.create_fiber_aware_client
          Fiber.new do
            client.connect
            expect do
              client.call(request)
            end.to raise_error(/test error/)
            EM.stop
          end.resume
        end
      end
    end

    context "when it has a file path" do
      let(:socket_path) { File.join(Dir.mktmpdir, "warden.sock") }
      it_should_behave_like "method missing payloads"
    end

    context "when it has a network path" do
      let(:socket_path) { 'tcp://localhost:43248' }
      it_should_behave_like "method missing payloads"
    end
  end

  describe "#method_missing with old API" do
    shared_examples_for "method missing old API payloads" do
      it "should return non-error payloads" do
        request = Warden::Protocol::EchoRequest.new(:message => "hello")
        response = Warden::Protocol::EchoResponse.new(:message => "world")

        handler = double()
        handler.should_receive(request.class.type_underscored).and_return(response)
        server = MockWardenServer.new(handler, socket_path)
        actual_response = nil

        em do
          server.start
          client = server.create_fiber_aware_client
          Fiber.new do
            client.connect
            actual_response = client.echo("hello")
            EM.stop
          end.resume
        end

        actual_response.should == "world"
      end

      it "should raise error payloads" do
        request = Warden::Protocol::EchoRequest.new(:message => "hello")
        response = MockWardenServer::Error.new("test error")

        handler = double()
        handler.should_receive(request.class.type_underscored).and_raise(response)
        server = MockWardenServer.new(handler, socket_path)

        em do
          server.start
          client = server.create_fiber_aware_client
          Fiber.new do
            client.connect
            expect do
              client.echo("hello")
            end.to raise_error(/test error/)
            EM.stop
          end.resume
        end
      end
    end

    context "when it has a file path" do
      let(:socket_path) { File.join(Dir.mktmpdir, "warden.sock") }
      it_should_behave_like "method missing old API payloads"
    end

    context "when it has a network path" do
      let(:socket_path) { 'tcp://localhost:43248' }
      it_should_behave_like "method missing old API payloads"
    end
  end
end
