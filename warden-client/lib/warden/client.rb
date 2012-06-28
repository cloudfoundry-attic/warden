require "socket"
require "warden/protocol"

module Warden

  class Client

    class Error       < StandardError; end
    class ServerError < Error; end

    attr_reader :path

    def initialize(path)
      @path = path
    end

    def connected?
      !@sock.nil?
    end

    def connect
      raise "already connected" if connected?
      @sock = ::UNIXSocket.new(path)
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

      wrapped_response = Warden::Protocol::WrappedResponse.decode(data)
      response = wrapped_response.response

      # Raise error replies
      if response.is_a?(Warden::Protocol::ErrorResponse)
        raise Warden::Client::ServerError.new(response.message)
      end

      response
    end

    def write(request)
      data = request.wrap.encode.to_s
      @sock.write data.length.to_s + "\r\n"
      @sock.write data + "\r\n"
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
