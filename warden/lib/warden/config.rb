# coding: UTF-8

require "membrane"

module Warden
  class Config
    def self.server_defaults
      {
        "unix_domain_path"        => "/tmp/warden.sock",
        "unix_domain_permissions" => 0755,
        "container_klass"         => "Warden::Container::Insecure",
        "container_grace_time"    => (5 * 60), # 5 minutes
        "job_output_limit"        => (10 * 1024 * 1024), # 10 megabytes
        "quota" => {
          "disk_quota_enabled" => true,
        },
        "allow_nested_warden" => false,
      }
    end

    def self.health_check_server_defaults
      {
        "port" => 2345,
      }
    end

    def self.server_schema
      ::Membrane::SchemaParser.parse do
        {
          "unix_domain_path"        => String,
          "unix_domain_permissions" => Integer,

          optional("container_rootfs_path") => String,
          optional("container_depot_path")  => String,

          "container_klass"       => String,
          "container_grace_time"  => enum(nil, Integer),

          # See getrlimit(2) for details. Integer values are passed verbatim.
          optional("container_rlimits") => {
            optional("as")         => Integer,
            optional("core")       => Integer,
            optional("cpu")        => Integer,
            optional("data")       => Integer,
            optional("fsize")      => Integer,
            optional("locks")      => Integer,
            optional("memlock")    => Integer,
            optional("msgqueue")   => Integer,
            optional("nice")       => Integer,
            optional("nofile")     => Integer,
            optional("nproc")      => Integer,
            optional("rss")        => Integer,
            optional("rtprio")     => Integer,
            optional("sigpending") => Integer,
            optional("stack")      => Integer,
          },

          "job_output_limit" => Integer,

          "quota" => {
            optional("disk_quota_enabled") => bool,
          },

          "allow_nested_warden" => bool,

          optional("pidfile") => enum(nil, String),

          optional("syslog_socket") => enum(nil, String),
        }
      end
    end

    def self.logging_defaults
      {
        "level" => "debug2",
      }
    end

    def self.logging_schema
      ::Membrane::SchemaParser.parse do
        {
          "level"            => String,
          optional("file")   => String,
          optional("syslog") => String,
        }
      end
    end

    def self.network_defaults
      {
        "pool_network"   => "10.254.0.0/24",
        "deny_networks"  => [],
        "allow_networks" => [],
        "allow_host_access" => false,
        "mtu"            => 1500,
      }
    end

    def self.network_schema
      ::Membrane::SchemaParser.parse do
        {
          # Preferred way to specify networks to pool
          optional("pool_network") => String,

          # Present for Backwards compatibility
          optional("pool_start_address") => String,
          optional("pool_size")          => Integer,
          optional("release_delay")          => Integer,
          optional("mtu")                => Integer,

          "deny_networks"      => [String],
          "allow_networks"     => [String],
          optional("allow_host_access") => bool,
        }
      end
    end

    def self.ip_local_port_range
      # if no ip_local_port_range found, make some guess"
      if File.exist?("/proc/sys/net/ipv4/ip_local_port_range")
        File.read("/proc/sys/net/ipv4/ip_local_port_range").split.map(&:to_i)
      else
        return 32768, 61000
      end
    end

    def self.port_defaults
      _, ephemeral_stop = self.ip_local_port_range
      start = ephemeral_stop + 1
      stop = 65000 + 1
      count = stop - start

      {
        "pool_start_port" => start,
        "pool_size"       => count,
      }
    end

    def self.port_schema
      ::Membrane::SchemaParser.parse do
        {
          "pool_start_port" => Integer,
          "pool_size"       => Integer,
        }
      end
    end

    def self.user_defaults
      {
        "pool_start_uid" => 10000,
        "pool_size"      => 64,
      }
    end

    def self.user_schema
      ::Membrane::SchemaParser.parse do
        {
          "pool_start_uid" => Integer,
          "pool_size"      => Integer,
        }
      end
    end

    attr_reader :config

    attr_reader :server
    attr_reader :health_check_server
    attr_reader :logging
    attr_reader :network
    attr_reader :port
    attr_reader :user

    def initialize(config)
      @config = config

      populate
      validate
      transform
    end

    def populate
      @server = self.class.server_defaults.merge(config["server"] || {})
      @health_check_server = self.class.health_check_server_defaults.
        merge(config["health_check_server"] || {})
      @logging = self.class.logging_defaults.merge(config["logging"] || {})
      @network = self.class.network_defaults.merge(config["network"] || {})
      @port = self.class.port_defaults.merge(config["port"] || {})
      @user = self.class.user_defaults.merge(config["user"] || {})
    end

    def validate
      self.class.server_schema.validate(@server)
      self.class.logging_schema.validate(@logging)
      self.class.network_schema.validate(@network)
      self.class.port_schema.validate(@port)
      self.class.user_schema.validate(@user)
    end

    def transform
      @server["container_klass"] = @server["container_klass"].
        split("::").
        inject(Kernel) { |prev, cur| prev.const_get(cur) }

      @network["deny_networks"]  = @network["deny_networks"].compact
      @network["allow_networks"] = @network["allow_networks"].compact

      # Transform pool_start_address/pool_size into pool_network if needed
      if @network.has_key?("pool_start_address") && @network.has_key?("pool_size")
        pool_start_address = @network.delete("pool_start_address")
        pool_size = @network.delete("pool_size").to_i

        # Determine number of fixed bits in netmask
        fixed_bits = Math.log2(pool_size).ceil + 2

        @network["pool_network"] = "%s/%d" % [pool_start_address, 32-fixed_bits]
      end
    end

    def rlimits
      @server["container_rlimits"] || {}
    end

    def allow_nested_warden?
      !!@server["allow_nested_warden"]
    end

    def to_hash
      {
        "server"  => server,
        "logging" => logging,
        "network" => network,
        "port"    => port,
        "user"    => user,
      }
    end
  end
end
