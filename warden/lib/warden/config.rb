# coding: UTF-8

require "membrane"

module Warden
  class Config
    def self.server_defaults
      {
        "unix_domain_path"        => "/tmp/warden.sock",
        "unix_domain_permissions" => 0755,
        "container_klass"         => "Warden::Container::Insecure",
        "container_grace_time"    => (5 * 60), # 5 minutes,
        "container_limits_conf"   => {
          "nofile" => 8192,    # max number of open files
          "nproc"  => 512,     # max number of processes
          "as"     => 4194304, # address space limit (KB)
        },
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
          "container_limits_conf" => {
            optional("core")         => Integer, # limits the core file size (KB)
            optional("data")         => Integer, # max data size (KB)
            optional("fsize")        => Integer, # maximum filesize (KB)
            optional("memlock")      => Integer, # max locked-in-memory address space (KB)
            optional("nofile")       => Integer, # max number of open files
            optional("rss")          => Integer, # max resident set size (KB)
            optional("stack")        => Integer, # max stack size (KB)
            optional("cpu")          => Integer, # max CPU time (MIN)
            optional("nproc")        => Integer, # max number of processes
            optional("as")           => Integer, # address space limit (KB)
            optional("maxlogins")    => Integer, # max number of logins for this user
            optional("maxsyslogins") => Integer, # max number of logins on the system
            optional("priority")     => Integer, # the priority to run user process with
            optional("locks")        => Integer, # max number of file locks the user can hold
            optional("sigpending")   => Integer, # max number of pending signals
            optional("msgqueue")     => Integer, # max memory used by POSIX message queues (bytes)
            optional("nice")         => Integer, # max nice priority allowed to raise to values: [-20, 19]
            optional("rtprio")       => Integer, # max realtime priority
          },
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
        "pool_start_address" => "10.254.0.0",
        "pool_size"          => 64,
        "deny_networks"      => [],
        "allow_networks"     => [],
      }
    end

    def self.network_schema
      ::Membrane::SchemaParser.parse do
        {
          "pool_start_address" => String,
          "pool_size"          => Integer,
          "deny_networks"      => [String],
          "allow_networks"     => [String],
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
    attr_reader :logging
    attr_reader :network
    attr_reader :user

    def initialize(config)
      @config = config

      populate
      validate
      transform
    end

    def populate
      @server = self.class.server_defaults.merge(config["server"] || {})
      @logging = self.class.logging_defaults.merge(config["logging"] || {})
      @network = self.class.network_defaults.merge(config["network"] || {})
      @user = self.class.user_defaults.merge(config["user"] || {})
    end

    def validate
      self.class.server_schema.validate(@server)
      self.class.logging_schema.validate(@logging)
      self.class.network_schema.validate(@network)
      self.class.user_schema.validate(@user)
    end

    def transform
      @server["container_klass"] = @server["container_klass"].
        split("::").
        inject(Kernel) { |prev, cur| prev.const_get(cur) }

      @network["deny_networks"]  = @network["deny_networks"].compact
      @network["allow_networks"] = @network["allow_networks"].compact
    end
  end
end
