# coding: UTF-8

require "warden/container/spawn"

module Warden

  module Container

    module Features

      module Cgroup

        def cgroup_path(subsystem)
          File.join("/tmp/warden/cgroup", subsystem.to_s, "instance-#{self.container_id}")
        end

        def restore
          super

          if @resources.has_key?("limit_cpu")
            limit_cpu(@resources["limit_cpu"])
          end
        end

        def do_info(request, response)
          super(request, response)

          begin
            fields = read_memory_stats
            response.memory_stat = Protocol::InfoResponse::MemoryStat.new(fields)
          rescue => e
            raise WardenError.new("Failed getting memory usage: #{e}")
          end

          begin
            fields = read_cpu_stats
            response.cpu_stat = Protocol::InfoResponse::CpuStat.new(fields)
          rescue => e
            raise WardenError.new("Failed getting cpu stats: #{e}")
          end

          nil
        end

        def limit_cpu(limit_in_shares)
          File.open(File.join(cgroup_path(:cpu), "cpu.shares"), 'w') do |f|
            f.write(limit_in_shares.to_s)
          end
        end

        private :limit_cpu

        def do_limit_cpu(request, response)
          if request.limit_in_shares
            begin
              limit_cpu(request.limit_in_shares)
            rescue => e
              raise WardenError.new("Failed setting cpu shares: #{e}")
            else
              @resources["limit_cpu"] = request.limit_in_shares
            end
          end

          limit_in_shares = File.read(File.join(cgroup_path(:cpu), "cpu.shares"))
          response.limit_in_shares = limit_in_shares.to_i

          nil
        end

        def read_memory_stats
          lines = File.read(File.join(cgroup_path(:memory), "memory.stat")).split(/\r?\n/)

          mem_stats = {}

          lines.map do |line|
            field, value = line.split(" ", 2)
            mem_stats[field.to_sym] = value.to_i
          end

          mem_stats
        end

        def read_cpu_stats
          cpu_stats = {}

          lines = File.read(File.join(cgroup_path(:cpuacct), "cpuacct.usage")).split(/\r?\n/)
          cpu_stats[:usage] = Integer(lines.first.strip)

          lines = File.read(File.join(cgroup_path(:cpuacct), "cpuacct.stat")).split(/\r?\n/)
          lines.map do |line|
            field, value = line.split(" ", 2)
            cpu_stats[field.to_sym] = Integer(value)
          end

          cpu_stats
        end
      end
    end
  end
end
