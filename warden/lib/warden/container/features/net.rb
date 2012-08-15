# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"

module Warden

  module Container

    module Features

      module Net

        include Spawn

        def self.included(base)
          base.extend(ClassMethods)
        end

        def do_info(request, response)
          super(request, response)
          id = request.handle
          in_info = sh "tc qdisc show dev w-#{id}-0 | grep rate | sed -r 's/.*: root refcnt [0-9]+ rate (\\S*) burst (\\S*) lat 25.0ms.*/\\1 \\2/'"
          out_info = sh "tc filter show dev w-#{id}-0 parent ffff: | grep rate | sed -r 's/.*police 0x[0-9a-f]+ rate (\\S*) burst (\\S*) mtu [0-9]+[KM]?b action drop overhead [0-9]+b.*/\\1 \\2/'"
          ret = {}
          {"in" => in_info, "out" => out_info}.each do |k, v|
            ret["#{k}_rate".to_sym], ret["#{k}_burst".to_sym] = (v.empty? ? ["Unlimited", "Unlimited"] : v.chomp.split(" ", 2))
          end
          response.bandwidth_stat = Protocol::InfoResponse::BandwidthStat.new(ret)
          nil
        end

        def do_limit_bandwidth(request, response)
          sh File.join(container_path, "net_rate.sh"), :env => {
            "BURST"     => request.burst,
						#bytes to bits
            "RATE"      => request.rate * 8,
          }
          response.rate = request.rate
          response.burst = request.burst
        end

        def do_net_in(request, response)
          host_port = self.class.port_pool.acquire

          # Use same port on the container side as the host side if unspecified
          container_port = request.container_port || host_port

          # Port may be re-used after this container has been destroyed
          @resources["ports"] << host_port
          @acquired["ports"] << host_port

          sh File.join(container_path, "net.sh"), "in", :env => {
            "HOST_PORT"      => host_port,
            "CONTAINER_PORT" => container_port,
          }

          response.host_port      = host_port
          response.container_port = container_port

        rescue WardenError
          self.class.port_pool.release(host_port)
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

          def setup(config = {})
            super(config)

            self.allow_networks = []
            if config["network"]
              self.allow_networks = [config["network"]["allow_networks"]].flatten.compact
            end

            self.deny_networks = []
            if config["network"]
              self.deny_networks = [config["network"]["deny_networks"]].flatten.compact
            end
          end
        end
      end
    end
  end
end
