require "warden/container/spawn"

module Warden

  module Container

    module Features

      module DiskUsage
        #XXX this stub should report actual disk usage.
        def get_info
          info = super
          info['stats']['disk_usage_B'] = 10000
          info
        end
      end
    end
  end
end
