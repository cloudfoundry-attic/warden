require "warden/protocol"

module Warden
  class Client
    class V1
      def self.request_from_v1(args)
        command = args.shift

        m = "convert_#{command}_request".downcase
        if respond_to?(m)
          send(m, args)
        else
          raise "Unknown command: #{command.upcase}"
        end
      end

      def self.response_to_v1(response)
        klass_name = response.class.name.split("::").last
        klass_name = klass_name.gsub(/Response$/, "")
        klass_name = klass_name.gsub(/(.)([A-Z])/) { |m| "#{m[0].chr}_#{m[1].chr}" }
        klass_name = klass_name.downcase

        m = "convert_#{klass_name}_response".downcase
        if respond_to?(m)
          send(m, response)
        else
          raise "Unknown response: #{response.class.name.split("::").last}"
        end
      end

      private

      def self.convert_create_request(args)
        request = Protocol::CreateRequest.new
        config = args.shift || {}

        config.each do |key, value|
          case key
          when "bind_mounts"
            bind_mounts = value.map do |src_path, dst_path, mode|
              bind_mount = Protocol::CreateRequest::BindMount.new
              bind_mount.src_path = src_path
              bind_mount.dst_path = dst_path

              if mode.kind_of?(Hash)
                mode = mode["mode"]
              end

              bind_mount.mode = Protocol::CreateRequest::BindMount::Mode.const_get(mode.to_s.upcase)
              bind_mount
            end

            request.bind_mounts = bind_mounts
          when "grace_time"
            request.grace_time = Integer(value)
          end
        end

        request
      end

      def self.convert_create_response(response)
        response.handle
      end

      def self.convert_stop_request(args)
        request = Protocol::StopRequest.new
        request.handle = args.shift
        request
      end

      def self.convert_stop_response(response)
        "ok"
      end

      def self.convert_destroy_request(args)
        request = Protocol::DestroyRequest.new
        request.handle = args.shift
        request
      end

      def self.convert_destroy_response(response)
        "ok"
      end

      def self.convert_info_request(args)
        request = Protocol::InfoRequest.new
        request.handle = args.shift
        request
      end

      def self.convert_info_response(response)
        stringify_hash response.to_hash
      end

      def self.convert_spawn_request(args)
        request = Protocol::SpawnRequest.new
        request.handle = args.shift
        request.script = args.shift
        request
      end

      def self.convert_spawn_response(response)
        response.job_id
      end

      def self.convert_link_request(args)
        request = Protocol::LinkRequest.new
        request.handle = args.shift
        request.job_id = Integer(args.shift)
        request
      end

      def self.convert_link_response(response)
        [response.exit_status, response.stdout, response.stderr]
      end

      def self.convert_stream_request(args)
        request = Protocol::StreamRequest.new
        request.handle = args.shift
        request.job_id = Integer(args.shift)
        request
      end

      def self.convert_stream_response(response)
        [response.name, response.data, response.exit_status]
      end

      def self.convert_run_request(args)
        request = Protocol::RunRequest.new
        request.handle = args.shift
        request.script = args.shift
        request
      end

      def self.convert_run_response(response)
        [response.exit_status, response.stdout, response.stderr]
      end

      def self.convert_net_request(args)
        request = nil
        handle = args.shift
        direction = args.shift

        case direction
        when "in"
          request = Protocol::NetInRequest.new
          request.handle = handle
        when "out"
          request = Protocol::NetOutRequest.new
          request.handle = handle

          network, port = args.shift.split(":", 2)
          request.network = network
          request.port = Integer(port)
        else
          raise "Unknown net direction: #{direction}"
        end

        request
      end

      def self.convert_net_in_response(response)
        stringify_hash response.to_hash
      end

      def self.convert_net_out_response(response)
        "ok"
      end

      def self.convert_copy_request(args)
        request   = nil
        handle    = args.shift
        direction = args.shift
        src_path  = args.shift
        dst_path  = args.shift
        owner     = args.shift

        attributes = {
          :handle => handle,
          :src_path => src_path,
          :dst_path => dst_path
        }

        case direction
        when "in"
          request = Protocol::CopyInRequest.new(attributes)
        when "out"
          request = Protocol::CopyOutRequest.new(attributes)
          request.owner = owner if owner
        else
          raise "Unknown copy direction: #{direction}"
        end

        request
      end

      def self.convert_copy_in_response(response)
        "ok"
      end

      def self.convert_copy_out_response(response)
        "ok"
      end

      def self.convert_limit_request(args)
        request = nil
        handle  = args.shift
        limit   = args.shift

        attributes = {
          :handle => handle,
        }

        case limit
        when "mem"
          request = Protocol::LimitMemoryRequest.new(attributes)
          request.limit_in_bytes = Integer(args.shift) unless args.empty?
        when "disk"
          request = Protocol::LimitDiskRequest.new(attributes)
          request.byte = Integer(args.shift) unless args.empty?
        when "bandwidth"
          request = Protocol::LimitBandwidthRequest.new(attributes)
          request.rate = Integer(args.shift) unless args.empty?
          request.burst = Integer(args.shift) unless args.empty?
        else
          raise "Unknown limit: #{limit}"
        end

        request
      end

      def self.convert_limit_memory_response(response)
        response.limit_in_bytes
      end

      def self.convert_limit_disk_response(response)
        response.byte
      end

      def self.convert_limit_bandwidth_response(response)
        "rate: #{response.rate} burst: #{response.burst}"
      end

      def self.convert_ping_request(args)
        request = Protocol::PingRequest.new
        request
      end

      def self.convert_ping_response(response)
        "pong"
      end

      def self.convert_list_request(args)
        request = Protocol::ListRequest.new
        request
      end

      def self.convert_list_response(response)
        response.handles
      end

      def self.convert_echo_request(args)
        request = Protocol::EchoRequest.new
        request.message = args.shift
        request
      end

      def self.convert_echo_response(response)
        response.message
      end

      private

      def self.stringify_hash(hash)
        Hash[hash.map do |key, value|
          if value.kind_of?(Hash)
            value = stringify_hash(value)
          end

          [key.to_s, value]
        end]
      end
    end
  end
end
