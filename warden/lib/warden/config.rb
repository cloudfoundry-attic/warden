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

    def rlimits
      @server["container_rlimits"] || {}
    end
  end
end
