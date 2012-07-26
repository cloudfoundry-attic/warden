# coding: UTF-8

require "steno"

module Warden

  module Logger

    def self.setup_logger(config = {})
      steno_config = {}
      steno_config[:context] = Steno::Context::ThreadLocal.new

      if config["level"]
        steno_config[:default_log_level] = config["level"]
      end

      sinks = []
      if config["file"]
        sinks << Steno::Sink::IO.for_file(config["file"])
      end

      if config["syslog"]
        Steno::Sink::Syslog.instance.open(config["syslog"])
        sinks << Steno::Sink::Syslog.instance
      end

      if sinks.empty?
        sinks << Steno::Sink::IO.new(STDOUT)
      end

      steno_config[:sinks] = sinks
      Steno.init(Steno::Config.new(steno_config))

      # Override existing logger instance
      @logger = Steno.logger("warden")
    end

    def self.logger?
      !! @logger
    end

    def self.logger
      @logger ||= setup_logger("level" => "info")
    end

    def self.logger=(logger)
      @logger = logger
    end


    Steno::Logger::LEVELS.each_key do |level|
      define_method(level) do |*args|
        prefix = logger_prefix_from_stack caller(1).first
        fmt = args.shift
        fmt = "%s: %s" % [prefix, fmt] if prefix
        Logger.logger.send(level, fmt, *args) if Logger.logger?
      end
    end

    protected

    def logger_prefix_from_stack(str)
      m = str.match(/^(.*):(\d+):in `(.*)'$/i)
      file, line, method = m[1], m[2], m[3]

      file_parts = File.expand_path(file).split("/")
      trimmed_file = file_parts.
        reverse.
        take_while { |e| e != "lib" }.
        map.
        with_index { |e,i| i == 0 ? e : e[0, 1] }.
        reverse.
        join("/")

      class_parts = self.class.name.split("::")
      trimmed_class = class_parts.
        reverse.
        map.
        with_index { |e,i| i == 0 ? e : e[0, 1].upcase }.
        reverse.
        join("::")

      "%s:%s - %s#%s" % [trimmed_file, line, trimmed_class, method]
    end
  end
end
