require "socket"
require "warden/protocol"
require "warden/client/v1"

module Warden

  class Client

    class Error       < StandardError; end
    class ServerError < Error; end

    attr_reader :path

    def initialize(path, port = nil)
      @path = path
      @port = port
      @v1mode = false
    end

    def connected?
      !@sock.nil?
    end

    def connect
      raise "already connected" if connected?
      if @port.nil?
        @sock = ::UNIXSocket.new(path)
      else
        @sock = ::TCPSocket.new(path, @port)
      end
    end

    def disconnect
      raise "not connected" unless connected?
      @sock.close rescue nil
      @sock = nil
    end

    def reconnect
      disconnect if connected?
      connect
    end

    def io
      rv = yield
      if rv.nil?
        disconnect
        raise ::EOFError
      end

      rv
    end

    def read
      length = io { @sock.gets }
      data = io { @sock.read(length.to_i) }

      # Discard \r\n
      io { @sock.read(2) }

      response = Warden::Protocol::Message.decode(data).response

      # Raise error replies
      if response.is_a?(Warden::Protocol::ErrorResponse)
        raise Warden::Client::ServerError.new(response.message)
      end

      if @v1mode
        response = V1.response_to_v1(response)
      end

      response
    end

    def write(request)
      if request.kind_of?(Array)
        @v1mode = true
        request = V1.request_from_v1(request.dup)
      end

      unless request.kind_of?(Warden::Protocol::BaseRequest)
        raise "Expected #kind_of? Warden::Protocol::BaseRequest"
      end

      data = request.wrap.encode.to_s
      @sock.write data.length.to_s + "\r\n"
      @sock.write data + "\r\n"
    end

    def stream(request, &blk)
      unless request.is_a?(Warden::Protocol::StreamRequest)
        msg = "Expected argument to be of type:"
        msg << "'#{Warden::Protocol::StreamRequest}'"
        msg << ", but received: '#{request.class}'."
        raise ArgumentError, msg
      end

      response = call(request)
      while response.exit_status.nil?
        blk.call(response)
        response = read
      end

      response
    end

    def call(request)
      write(request)
      read
    end

    def method_missing(sym, *args, &blk)
      klass_name = sym.to_s.gsub(/(^|_)([a-z])/) { $2.upcase }
      klass_name += "Request"
      klass = Warden::Protocol.const_get(klass_name)

      call(klass.new(*args))
    end
  end
end
