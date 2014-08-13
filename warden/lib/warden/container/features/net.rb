# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"

module Warden

  module Container

    module Features

      module Net

        include Spawn

        INREG = /qdisc tbf [0-9a-f]+: root refcnt \d+ rate (\d+)([KMG]?)bit burst (\d+)([KMG]?)b lat 25.0ms/
        OUTREG = /\s*police 0x[0-9a-f]+ rate (\d+)([KMG]?)bit burst (\d+)([KMG]?)b mtu \d+[KM]?b action drop overhead \d+b/

        def self.included(base)
          base.extend(ClassMethods)
        end

        def to_num(val, suffix)
          kmg_map = {
            "G" => 10 ** 9,
            "M" => 10 ** 6,
            "K" => 10 ** 3,
          }
          factor = kmg_map[suffix] || 1
          val * factor
        end

        def restore
          super

          # Re-run container-specific networking setup to make sure the
          # container-specific chains are in place
          sh(File.join(container_path, "net.sh"), "setup")

          if @resources.has_key?("net_in")
            @resources["net_in"].each do |host_port, container_port|
              _net_in(host_port, container_port)
            end
          end

          if @resources.has_key?("net_out")
            @resources["net_out"].each do |args|
              _net_out(*args)
            end
          end
        end

        def do_info(request, response)
          super(request, response)

          container_id = self.class.registry[request.handle].container_id

          ret = {}

          {:in => {:bash_key =>  "get_egress_info", :reg => INREG, :rate_key => :in_rate, :burst_key => :in_burst},
            :out => {:bash_key => "get_ingress_info", :reg => OUTREG, :rate_key => :out_rate, :burst_key => :out_burst}}.each do |k, v|

            # Set default rate value to 0xffffffff default burst value to 0xffffffff
            ret[v[:rate_key]], ret[v[:burst_key]] = [0xffffffff, 0xffffffff]
            info = sh File.join(container_path, "net.sh"), v[:bash_key], :env => {
              "ID" => container_id
            }
            info.split("\n").each do |line|
              if band_info = v[:reg].match(line)
                ret[v[:rate_key]] = to_num(band_info[1].to_i, band_info[2]) / 8 # Bits to bytes
                ret[v[:burst_key]] = to_num(band_info[3].to_i, band_info[4])
                break
              end
            end
          end

          response.bandwidth_stat = Protocol::InfoResponse::BandwidthStat.new(ret)
          nil
        end

        def do_limit_bandwidth(request, response)
          sh File.join(container_path, "net_rate.sh"), :env => {
            "BURST" => request.burst,
            "RATE"  => request.rate * 8, # Bytes to bits
          }
          response.rate = request.rate
          response.burst = request.burst
        end

        def _net_in(host_port, container_port)
          sh File.join(container_path, "net.sh"), "in", :env => {
            "HOST_PORT"      => host_port,
            "CONTAINER_PORT" => container_port,
          }
        end

        def do_net_in(request, response)
          if request.host_port.nil?
            host_port = self.class.port_pool.acquire

            # Use same port on the container side as the host side if unspecified
            container_port = request.container_port || host_port

            # Port may be re-used after this container has been destroyed
            @resources["ports"] << host_port
            @acquired["ports"] << host_port
          else
            host_port = request.host_port
            container_port = request.container_port || host_port
          end

          _net_in(host_port, container_port)

          @resources["net_in"] ||= []
          @resources["net_in"] << [host_port, container_port]

          response.host_port      = host_port
          response.container_port = container_port
        rescue WardenError
          self.class.port_pool.release(host_port) unless request.host_port
          raise
        end

        def _net_out(network, port_range, protocol, icmp_type, icmp_code, log)
          sh File.join(container_path, "net.sh"), "out", :env => {
            "NETWORK" => network,
            "PORTS"    => port_range,
            "PROTOCOL" => protocol,
            "ICMP_TYPE" => icmp_type,
            "ICMP_CODE" => icmp_code,
            "LOG" => log,
          }
        end

        def do_net_out(request, response)
          unless request.network || request.port || request.port_range
            raise WardenError.new("Please specify network, port, and/or port_range.")
          end

          port_range = request.port_range || "#{request.port}"
          validate_port_range(port_range)
          icmp_type = nil
          icmp_code = nil

          case request.protocol
            when Warden::Protocol::NetOutRequest::Protocol::TCP
              protocol = "tcp"
            when Warden::Protocol::NetOutRequest::Protocol::UDP
              protocol = "udp"
            when Warden::Protocol::NetOutRequest::Protocol::ICMP
              icmp_type = request.icmp_type unless request.icmp_type == -1
              icmp_code = request.icmp_code unless request.icmp_code == -1
              protocol = "icmp"
            when Warden::Protocol::NetOutRequest::Protocol::ALL
              protocol = "all"
            else
              protocol = "tcp"
          end

          _net_out(request.network, port_range, protocol, icmp_type, icmp_code, request.log)

          @resources["net_out"] ||= []
          @resources["net_out"] << [request.network, port_range, protocol, icmp_type, icmp_code, request.log]
        end

        def acquire(opts = {})
          if !@resources.has_key?("ports")
            @resources["ports"] = []
            @acquired["ports"] = []
          else
            @acquired["ports"] = @resources["ports"].dup
          end

          super
        end

        def release
          if ports = @acquired.delete("ports")
            ports.each { |port| self.class.port_pool.release(port) }
          end

          super
        end

        module ClassMethods

          include Spawn

          # Network blacklist
          attr_accessor :deny_networks

          # Network whitelist
          attr_accessor :allow_networks

          def setup(config)
            super(config)

            self.deny_networks  = config.network["deny_networks"]
            self.allow_networks = config.network["allow_networks"]
          end
        end

        private

        def validate_port_range(port_range)
          return if port_range.nil?
          return unless port_range.include? ":"
          min_port, max_port = port_range.split(":")
          raise WardenError.new("Port range maximum must be greater than minimum") unless min_port.to_i < max_port.to_i
        end
      end
    end
  end
end
