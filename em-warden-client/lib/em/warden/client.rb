require 'eventmachine'
require 'fiber'
require 'uri'

require 'em/warden/client/connection'
require 'em/warden/client/error'

module EventMachine
  module Warden
  end
end

class EventMachine::Warden::FiberAwareClient

  attr_reader :socket_path

  def initialize(socket_path)
    @socket_path = socket_path
    @connection  = nil
  end

  def connect
    return if @connection

    @connection = EM.connect(*connection_args)

    f = Fiber.current
    @connection.on(:connected) { f.resume }
    Fiber.yield
  end

  def connected?
    @connection.connected?
  end

  def call(*args, &blk)
    raise EventMachine::Warden::Client::Error.new("Not connected") unless @connection.connected?

    f = Fiber.current
    @connection.call(*args) do |res|
      logger.info "Calling a dead fiber: #{f.object_id}, Response: #{res.inspect}" if !f.alive?
      f.resume(res)
    end
    result = Fiber.yield

    result.get
  end

  def method_missing(method, *args, &blk)
    call(method, *args, &blk)
  end

  def disconnect(close_after_writing=true)
    @connection.close_connection(close_after_writing)
    f = Fiber.current
    @connection.on(:disconnected) { f.resume }
    Fiber.yield
  end

  private
  def connection_args
    uri = URI.parse(socket_path)

    if uri.absolute?
      [uri.host, uri.port, EM::Warden::Client::Connection]
    else
      [uri.path, EM::Warden::Client::Connection]
    end
  end

  def logger
    @logger ||= Logger.new(STDOUT)
    @logger
  end
end
