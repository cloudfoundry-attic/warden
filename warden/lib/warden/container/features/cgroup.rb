# coding: UTF-8

require "warden/container/spawn"

module Warden

  module Container

    module Features

      module Cgroup

        def cgroup_path(subsystem)
          File.join("/sys/fs/cgroup", subsystem.to_s, "instance-#{self.handle}")
        end

        def do_info(request, response)
          super(request, response)

          begin
            lines = File.read(File.join(cgroup_path(:memory), "memory.stat")).split(/\r?\n/)

            fields = Hash[lines.map do |line|
              field, value = line.split(" ", 2)
              [field.to_sym, value.to_i]
            end]

            response.memory_stat = Protocol::InfoResponse::MemoryStat.new(fields)

          rescue => e
            raise WardenError.new("Failed getting memory usage: #{e}")
          end

          nil
        end
      end
    end
  end
end
