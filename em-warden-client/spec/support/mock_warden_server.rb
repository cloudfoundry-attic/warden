require "eventmachine"
require "tmpdir"
require "warden/protocol/buffer"
require "em/warden/client"

class MockWardenServer
  class Error < StandardError
  end

  class ClientConnection < ::EM::Connection
    def initialize(handler = nil)
      super()

      @handler = handler
      @buffer  = ::Warden::Protocol::Buffer.new
    end

    def send_response(response)
      send_data ::Warden::Protocol::Buffer.response_to_wire(response)
    end

    def send_error(err)
      send_response ::Warden::Protocol::ErrorResponse.new(:message => err.message)
    end

    def receive_data(data = nil)
      @buffer << data if data
      @buffer.each_request do |request|
        begin
          response = @handler.send(request.type_underscored, request)
          send_response(response)
        rescue MockWardenServer::Error => err
          send_error(err)
        end
      end
    end
  end

  attr_reader :socket_path

  def initialize(handler = nil)
    @handler     = handler
    @server_sig  = nil
    @tmpdir      = Dir.mktmpdir
    @socket_path = File.join(@tmpdir, "warden.sock")
  end

  def start
    @server_sig = ::EM.start_unix_domain_server(@socket_path, ClientConnection, @handler)
  end

  def create_connection
    ::EM.connect_unix_domain(@socket_path, EM::Warden::Client::Connection)
  end

  def create_fiber_aware_client
    ::EM::Warden::FiberAwareClient.new(@socket_path)
  end

  def stop
    ::EM.stop_server(@server_sig)
    @server_sig = nil
  end
end

def create_mock_handler(request, response = nil)
  handler = mock()
  mock_cont = handler.should_receive(request.type_underscored)
  mock_cont = mock_cont.with(request)

  if response
    if response.kind_of?(StandardError)
      mock_cont.and_raise(response)
    else response
      mock_cont.and_return(response)
    end
  else
    mock_cont.and_return(request.create_response)
  end

  handler
end
