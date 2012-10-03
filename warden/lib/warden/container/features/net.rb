# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"

module Warden

  module Container

    module Features

      module Net

        include Spawn

        INREG = /qdisc tbf \d+: root refcnt \d+ rate (\d+)([KMG]?)bit burst (\d+)([KMG]?)b lat 25.0ms/
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

        def do_info(request, response)
          super(request, response)

          id = request.handle

          ret = {}

          {:in => {:bash_key =>  "get_egress_info", :reg => INREG, :rate_key => :in_rate, :burst_key => :in_burst},
            :out => {:bash_key => "get_ingress_info", :reg => OUTREG, :rate_key => :out_rate, :burst_key => :out_burst}}.each do |k, v|

            # Set default rate value to 0xffffffff default burst value to 0xffffffff
            ret[v[:rate_key]], ret[v[:burst_key]] = [0xffffffff, 0xffffffff]
            info = sh File.join(container_path, "net.sh"), v[:bash_key], :env => {
              "ID" => id
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

          sh File.join(container_path, "net.sh"), "in", :env => {
            "HOST_PORT"      => host_port,
            "CONTAINER_PORT" => container_port,
          }

          response.host_port      = host_port
          response.container_port = container_port

        rescue WardenError
          self.class.port_pool.release(host_port) unless request.host_port
          raise
        end

        def do_net_out(request, response)
          sh File.join(container_path, "net.sh"), "out", :env => {
            "NETWORK" => request.network,
            "PORT"    => request.port,
          }
        end

        def acquire
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
      end
    end
  end
end
