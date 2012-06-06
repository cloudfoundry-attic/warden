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

        def do_net_in
          port = self.class.port_pool.acquire

          # Port may be re-used after this container has been destroyed
          on(:after_destroy) {
            self.class.port_pool.release(port)
          }

          sh *[ %{env},
                %{PORT=%s} % port,
                %{%s/net.sh} % container_path,
                %{in} ]

          port

        rescue WardenError
          PortPool.release(port)
          raise
        end

        def do_net_out(spec)
          network, port = spec.split(":")

          sh *[ %{env},
                %{NETWORK=%s} % network,
                %{PORT=%s} % port,
                %{%s/net.sh} % container_path,
                %{out} ]

          "ok"
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
