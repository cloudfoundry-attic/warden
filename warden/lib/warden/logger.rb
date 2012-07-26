# coding: UTF-8

require "steno"

module Warden

  module Logger

    def self.setup_logger(config = {})
      steno_config = Steno::Config.to_config_hash(config)
      steno_config[:context] = Steno::Context::FiberLocal.new
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
        message = args.shift
        message = message.to_s unless message.is_a? String
        Logger.logger.send(level, message) if Logger.logger? and message
      end
    end
  end
end
