# coding: UTF-8
# TODO(kowshik): Convert run from spawn(link(cmd)) to spawn(stream(cmd))

require "warden/client"
require "warden/protocol"
require "warden/commands_manager"

require "readline"
require "shellwords"
require "json"
require "pp"
require "optparse"

module Warden
  class Repl

    include Warden::CommandsManager

    class ReplError < StandardError
    end

    def initialize(opts={})
      @trace = opts[:trace] == true
      @socket_path = opts[:socket_path] || "/tmp/warden.sock"
      @client = Warden::Client.new(@socket_path)
      @history_path = opts[:history_path] || File.join(ENV['HOME'], '.warden-history')
      @commands = command_descriptions.keys
    end

    def start
      restore_history

      @client.connect unless @client.connected?

      comp = proc { |s|
        @commands.keys.grep( /^#{Regexp.escape(s)}/ )
      }

      Readline.completion_append_character = " "
      Readline.completion_proc = comp

      while line = Readline.readline('warden> ', true)
        begin
          if command_info = process_line(line)
            save_history
            puts command_info[:result]
          end
        rescue Warden::Repl::ReplError => re
          puts re.message
        end
      end
    end

    def process_line(line)
      line ||= ""
      line = line.strip
      return if line.empty?

      command_args = Shellwords.shellsplit(line)
      process_command(*command_args)
    end

    def process_command(*command_args)
      puts "+ #{command_args.join(" ")}" if @trace

      command_info = {}

      begin
        type, obj = deserialize(command_args)

        case type
        when :help
          command_info[:result] = self.class.describe_commands
        when :command_help
          command_info[:result] = self.class.describe_command(obj)
        else
          @client.connect() unless @client.connected?
          response = nil

          if type == :stream
            process_stream = lambda do |response|
              if response.name.downcase == "stdout"
                STDOUT.write(response.data)
              else
                STDERR.write(response.data)
              end
            end

            response = @client.stream(obj, &process_stream)
          else
            response = @client.send(type, obj)
          end

          command_info[:exit_status] = response.exit_status if type == :run
          serialized = serialize(response)
          command_info[:result] = self.class.describe_response(serialized)
        end
      rescue => e
        raise ReplError, e.message
      end

      command_info
    end



    class << self
      def describe_response(serialized_response)
        text = ""
        serialized_response.each_pair do |field, description|
          text << "#{field} : #{description}\n"
        end
        text
      end

      def describe_command(command_info)
        cmd_name = command_info.keys[0]
        cmd_help = command_info[cmd_name]
        usage = "command: #{cmd_name}\n"
        usage << "description: #{cmd_help[:description]}\n"
        options = describe_options(cmd_help, 1)

        if options && !options.empty?
          usage << "usage: #{command_info[:name]} [options]\n\n"
          usage << "[options] can be one of the following:\n\n"
          usage << options
        end

        usage
      end

      def describe_options(command_help, indent_level = 0)
        options = ''
        do_describe_options(command_help, options, indent_level)
        options
      end

      def do_describe_options(command_help, text, indent_level = 0)
        [:required, :repeated, :optional].each do |field_type|
          if fields = command_help[field_type]
            fields.each_pair do |name, help|
              text << "\t" * indent_level
              if help.is_a?(String)
                text << help
                text << "\n"
              elsif help.is_a?(Hash)
                text << help[:description]
                text << "\n"
                do_describe_options(help, text, indent_level + 1)
              end
            end
          end
        end

        text
      end

      def describe_commands(command_list_width = 0)
        command_list_width ||= 0
        if !(command_list_width.is_a?(Integer) && command_list_width >= 0)
          raise ArgumentError, "command_list_width should be a non-negative Integer."
        end

        text = ''

        unless command_list_width > 0
          command_descriptions.each do |command, description|
            command_list_width = command.size if command.size > command_list_width
          end

          command_list_width += 2
        end

        command_descriptions.each_pair do |command, description|
          text << "\t%-#{command_list_width}s%s\n" % [command, description]
        end

        text
      end
    end

    private

    def save_history
      marshalled = Readline::HISTORY.to_a.to_json
      open(@history_path, 'w+') {|f| f.write(marshalled)}
    end

    def restore_history
      return unless File.exists? @history_path
      open(@history_path, 'r') do |file|
        history = JSON.parse(file.read)
        history.map {|line| Readline::HISTORY.push line}
      end
    end
  end
end
