require 'pathname'

module Warden
  class MountPoint
    def for_path(path)
      path_name = Pathname.new(path).realpath

      until path_name.mountpoint? do
        path_name = path_name.parent.realpath
      end

      path_name.to_s
    end
  end
end