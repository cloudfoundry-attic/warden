# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class Buffer
      CRLF = "\r\n"

      def self.request_to_wire(request)
        unless request.kind_of?(BaseRequest)
          raise ArgumentError, "Expected #kind_of? ::%s" % BaseRequest.name
        end
        payload_to_wire request.wrap.encode.to_s
      end

      def self.response_to_wire(response)
        unless response.kind_of?(BaseResponse)
          raise ArgumentError, "Expected #kind_of? ::%s" % BaseResponse.name
        end
        payload_to_wire response.wrap.encode.to_s
      end

      def initialize
        @buffer = ""
      end

      def <<(data)
        @buffer += data
      end

      def each_request(&blk)
        each do |payload|
          yield(Warden::Protocol::Message.decode(payload).request)
        end
      end

      def each_response(&blk)
        each do |payload|
          yield(Warden::Protocol::Message.decode(payload).response)
        end
      end

      protected

      def self.payload_to_wire(payload)
        payload.to_s.length.to_s + CRLF + payload.to_s + CRLF
      end

      def each
        loop do
          crlf = @buffer.index(CRLF)
          break unless crlf

          length = Integer(@buffer[0...crlf])
          protocol_length = crlf + 2 + length + 2
          break unless @buffer.length >= protocol_length

          payload = @buffer[crlf + 2, length]

          # Trim buffer
          @buffer = @buffer[protocol_length..-1]

          yield(payload)
        end
      end
    end
  end
end
