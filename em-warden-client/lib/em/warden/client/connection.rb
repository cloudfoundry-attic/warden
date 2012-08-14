require "eventmachine"
require "warden/client"
require "warden/client/v1"
require "warden/protocol/buffer"
require "em/warden/client/error"
require "em/warden/client/event_emitter"

module EventMachine
  module Warden
    module Client
    end
  end
end

class EventMachine::Warden::Client::Connection < ::EM::Connection
  include EM::Warden::Client::EventEmitter

  class CommandResult
    def initialize(value)
      @value = value
    end

    def get
      if @value.kind_of?(StandardError)
        raise @value
      else
        @value
      end
    end
  end

  def post_init
    @request_queue   = []
    @current_request = nil
    @connected       = false
    @buffer          = ::Warden::Protocol::Buffer.new

    on(:connected) do
      @connected = true
    end

    on(:disconnected) do
      @connected = false
    end
  end

  def connected?
    @connected
  end

  def connection_completed
    emit(:connected)
  end

  def unbind
    emit(:disconnected)
  end

  def call(*args, &blk)
    if args.first.kind_of?(::Warden::Protocol::BaseRequest)
      request = args.first
    else
      # Use array when single array is passed
      if args.length == 1 && args.first.is_a?(::Array)
        args = args.first
      end

      # Create request from array
      request = ::Warden::Client::V1.request_from_v1(args.dup)
      @v1mode = true
    end

    @request_queue << { :request => request, :callback => blk }

    process_queue
  end

  def method_missing(method, *args, &blk)
    call(*([method] + args), &blk)
  end

  def receive_data(data = nil)
    @buffer << data if data
    @buffer.each_response do |response|
      # Transform response if needed
      if response.is_a?(Warden::Protocol::ErrorResponse)
        response = EventMachine::Warden::Client::Error.new(response.message)
      else
        if @v1mode
          response = Warden::Client::V1.response_to_v1(response)
        end
      end

      unless @current_request
        raise "Logic error! Received reply without a corresponding request"
      end

      if @current_request[:callback]
        @current_request[:callback].call(CommandResult.new(response))
      end

      @current_request = nil
    end

    process_queue
  end

  def process_queue
    return if @current_request || @request_queue.empty?

    @current_request = @request_queue.shift

    send_data(::Warden::Protocol::Buffer.request_to_wire(@current_request[:request]))
  end
end
