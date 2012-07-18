# coding: UTF-8

require "warden/errors"
require "warden/container/spawn"

module Warden

  module Container

    module Features

      module Net

        include Spawn

        def self.included(base)
          base.extend(ClassMethods)
        end

        def do_net_in(request, response)
          host_port = self.class.port_pool.acquire

          # Use same port on the container side as the host side if unspecified
          container_port = request.container_port || host_port

          # Port may be re-used after this container has been destroyed
          on(:after_destroy) {
            self.class.port_pool.release(host_port)
          }

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
