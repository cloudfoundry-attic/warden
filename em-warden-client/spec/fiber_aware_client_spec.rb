require "spec_helper"
require "support/mock_warden_server"

describe EventMachine::Warden::FiberAwareClient do
  describe "#connected" do
    it "should yield the calling fiber until connected" do
      server = MockWardenServer.new

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

  describe "#disconnect" do
    it "should yield the calling fiber until disconnected" do
      server = MockWardenServer.new

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

  describe "#method_missing" do
    it "should return non-error payloads" do
      request = Warden::Protocol::EchoRequest.new(:message => "hello")
      expected_response = Warden::Protocol::EchoResponse.new(:message => "world")

      handler = mock()
      handler.should_receive(request.class.type_underscored).and_return(expected_response)
      server = MockWardenServer.new(handler)
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

      handler = mock()
      handler.should_receive(request.class.type_underscored).and_raise(expected_response)
      server = MockWardenServer.new(handler)

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

  describe "#method_missing with old API" do
    it "should return non-error payloads" do
      request = Warden::Protocol::EchoRequest.new(:message => "hello")
      response = Warden::Protocol::EchoResponse.new(:message => "world")

      handler = mock()
      handler.should_receive(request.class.type_underscored).and_return(response)
      server = MockWardenServer.new(handler)
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

      handler = mock()
      handler.should_receive(request.class.type_underscored).and_raise(response)
      server = MockWardenServer.new(handler)

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
end
