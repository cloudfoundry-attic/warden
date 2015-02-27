# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class Message
      module Type
        def self.generate_klass_map(suffix)
          map = Hash[self.constants.map do |name|
            klass_name = "#{name}#{suffix}"
            if Protocol.const_defined?(klass_name)
              [const_get(name), Protocol.const_get(klass_name)]
            end
          end.compact]

          if map.respond_to?(:default_proc=)
            map.default_proc = lambda do |h, k|
              raise "Unknown request type: #{k}"
            end
          end

          map
        end

        def self.to_request_klass(type)
          @request_klass_map ||= generate_klass_map("Request")
          @request_klass_map[type]
        end

        def self.to_response_klass(type)
          @response_klass_map ||= generate_klass_map("Response")
          @response_klass_map[type]
        end
      end

      def request
        safe do
          Type.to_request_klass(type).decode(payload)
        end
      end

      def response
        safe do
          Type.to_response_klass(type).decode(payload)
        end
      end
    end
  end
end
