# coding: UTF-8

require "warden/client"
require "warden/repl/commands_manager"

require "readline"
require "shellwords"
require "pp"
require "optparse"
require "yajl"

module Warden::Repl
  # Runs either interactively (or) non-interactively. Returns the output
  # and exit status of a command and raises errors (if any) in non-interactive
  # execution. Autocompletes commands, writes their output to standard out and
  # writes the errors to standard error in interactive execution.
  class Repl

    include Warden::Repl::CommandsManager

    # Parameters:
    # - opts [Hash]
    #      Set :trace to true to log every command executed with a "+" prefix.
    #      Set :socket_path to a custom file path to be used to connect to the
    #         Warden server.
    #      Set :history_path to a custom file path to where history of commands
    #         being executed should be saved.
    #      Set :exit_on_error to true if you want the Repl to stop after the
    #         first command that returns a non-zero exit status, or stop after
    #         handling the first error in processing commands.
    def initialize(opts = {})
      @exit_on_error = opts[:exit_on_error]
      @exit_on_error = false unless @exit_on_error
      @trace = opts[:trace] == true
      @socket_path = opts[:socket_path] || "/tmp/warden.sock"
      @client = Warden::Client.new(@socket_path)
      @history_path = opts[:history_path] || File.join(ENV['HOME'],
                                                       '.warden-history')
      @commands = command_descriptions.keys # for Readline's keyword completion
    end

    # Starts an interactive client that uses the 'warden> ' prompt to accept
    # commands interactively. Autocompletes commands on the prompt when the tab
    # key is pressed. Writes the output of the command to standard out and
    # errors to standard error. Also saves and restores the command history
    # from a specified file.
    #
    # If error_on_exit flag is set, then returns an integer representing the
    # exit status (if any) returned by the last command that was executed
    # successfully. Otherwise, returns zero.
    def start
      restore_history
      @client.connect unless @client.connected?

      comp = proc { |s|
        @commands.grep( /^#{Regexp.escape(s)}/ )
      }

      Readline.completion_append_character = " "
      Readline.completion_proc = comp

      exit_status = 0
      while line = Readline.readline('warden> ', true)
        command_info = nil

        begin
          if command_info = process_line(line)
            save_history
            STDOUT.write("#{command_info[:result]}")
          end
        rescue Warden::Protocol::ProtocolError,
          Warden::Client::ServerError,
          Warden::Repl::CommandsManager::CommandError => ce
          STDERR.write("#{ce.message}\n")
          break if @exit_on_error
        rescue Errno::EPIPE
          STDOUT.write("Reconnecting...")
          @client.disconnect
          @client.connect
          STDOUT.write("\n")
          retry
        end

        if @exit_on_error
          if command_info && command_info[:exit_status]
            exit_status = command_info[:exit_status]
          end

          break if exit_status != 0
        end
      end

      exit_status
    end

    # Executes the Warden command passed and returns the result and exit status.
    #
    # Parameters:
    # - line [String]:
    #      Command to be executed.
    #
    # Returns:
    #    Hash with the following keys and values:
    #       :result => Output of the command. [String]
    #       :exit_status => Exit status of the command [Integer]
    #
    # Raises:
    # - Warden::CommandsManager::CommandError:
    #      When command and/or its arguments are wrong.
    def process_line(line)
      line ||= ""
      line = line.strip
      return if line.empty?

      begin
        process_command(Shellwords.shellsplit(line))
      rescue ArgumentError => e
        raise CommandError, e.message
      end
    end

    # Returns a prettified description [String] of all commands defined in the
    # Warden protocol gem.
    #
    # Parameters:
    # - command_list_width [Integer]:
    #       Non-negative integer that can be used format the width to be
    #       printed between a command name and its description. The default
    #       value of zero formats the width to be two whitespaces more than the
    #       longest command name defined among all commands.
    def describe_commands(command_list_width = 0)
      command_list_width ||= 0
      if !(command_list_width.is_a?(Integer) && command_list_width >= 0)
        raise ArgumentError, "command_list_width should be a non-negative Integer."
      end

      text = "\n"

      unless command_list_width > 0
        command_descriptions.each do |command, description|
          command_list_width = command.size if command.size > command_list_width
        end

        command_list_width += 2
      end

      command_descriptions.each_pair do |command, description|
        # TODO: Need to eliminate special case for run command.
        if command == "run"
          description = self.class.run_command_description
        end

        text << "\t%-#{command_list_width}s%s\n" % [command, description]
      end

      text << "\t%-#{command_list_width}s%s\n" % ["help", "Show help."]
      text << "\nUse --help with each command for more information.\n"
      text
    end

    def to_type(klass)
      type = klass.name.gsub(/(Request|Response)$/, "")
      type = type.split("::").last
      type = type.gsub(/(.)([A-Z])/, "\\1_\\2").downcase
      type
    end

    def process_command(command_args)
      command_info = { :result => "" }
      command_info[:result] << "+ #{command_args.join(" ")}\n" if @trace

      command = deserialize(command_args)

      if !command
        command_info[:result] = describe_commands
      elsif command.is_a?(Hash)
        command_info[:result] = describe_command(command)
      else
        @client.connect() unless @client.connected?

        type = to_type(command.class).to_sym

        if type == :stream || type == :run
          process_stream = lambda do |response|
            stream_name  = response.name.downcase

            STDOUT.write(response.data) if stream_name == "stdout"
            STDERR.write(response.data) if stream_name == "stderr"
          end

          # TODO: Need to eliminate special case for run command.
          command = to_stream_command(command) if type == :run
          response = @client.stream(command, &process_stream)
          command_info[:exit_status] = response.exit_status if type == :run
        else
          response = @client.call(command)
          command_info[:result] << describe_response(serialize(response))
        end
      end

      command_info
    end

    private

    def to_stream_command(command)
      spawn_command = convert_to_spawn_command(command)
      generate_stream_command(spawn_command, @client.call(spawn_command))
    end

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
      usage << "description: "
      # TODO: Need to eliminate special case for run command.
      if cmd_name == :run
        usage << self.class.run_command_description
      else
        usage << "#{cmd_help[:description]}"
      end
      usage << "\n"

      options = describe_options(cmd_help, 1)

      if options && !options.empty?
        usage << "usage: #{cmd_name} [options]\n\n"
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

    def save_history
      marshalled = Yajl::Encoder.encode(Readline::HISTORY.to_a, :check_utf8 => false)
      open(@history_path, 'w+') {|f| f.write(marshalled)}
    end

    def restore_history
      return unless File.exists? @history_path
      open(@history_path, 'r') do |file|
        history = Yajl::Parser.parse(file.read, :check_utf8 => false)
        history.map {|line| Readline::HISTORY.push line}
      end
    end

    def self.run_command_description
      description = "Short hand for spawn(stream(cmd))"
      description << " i.e. spawns a command, streams the result."

      description
    end
  end
end
