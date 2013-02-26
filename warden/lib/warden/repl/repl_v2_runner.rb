require "optparse"
require "warden/repl/repl_v2"
require "warden/repl/commands_manager"

module Warden::Repl
  class ReplRunner

    # Parses command-line arguments, runs Repl and handles the output and exit
    # status of commands.
    #
    # Parameters:
    # - args [Array of Strings]:
    #      Command-line arguments to be parsed.
    def self.run(args = [])
      options = {}

      opt_parser = OptionParser.new do |op|
        op.banner = <<-EOT
Usage: warden [options] -- [commands]
Runs an interactive REPL by default.

[options] can be one of the following:

EOT
        op.on("--socket socket", "Warden socket path.") do |socket_path|
          options[:socket_path] = socket_path
        end

        op.on("--trace", "Writes each command preceded by a '+' to stdout before" \
              + " executing.") do |trace|
          options[:trace] = true
        end

        op.on("--exit_on_error",
              "Exit after the first unsuccessful command.") do
          options[:exit_on_error] = true
        end

        op.on_tail("--help", "Show help.") do
          puts op
          puts
          puts "[commands] can be one of the following separated by a newline."
          puts Warden::Repl::Repl.new.describe_commands(op.summary_width - 3)
          puts
          exit
        end
      end

      global_args = []
      command = []
      delimiter_found = false
      args.each do |element|
        element = element.dup
        if element == "--"
          raise "Delimiter: '--' specified multiple times." if delimiter_found
          delimiter_found = true
        else
          if delimiter_found
            command << element
          else
            global_args << element
          end
        end
      end

      opt_parser.parse(global_args)
      repl = Warden::Repl::Repl.new(options)

      if command.empty?
        run_interactively(repl)
      else
        run_non_interactively(repl, command)
      end
    end

    private

    def self.run_interactively(repl)
      trap('INT') do
        STDERR.write("\n\nExiting...\n")
        exit
      end

      exit(repl.start)
    end

    def self.run_non_interactively(repl, command)
      command_info = nil

      begin
        command_info = repl.process_command(command)
      rescue Warden::Repl::CommandsManager::CommandError => ce
        STDERR.write("#{ce}\n")
        ce.backtrace.each { |err| STDERR.write("#{err}\n") }
      end

      exit_status = 0
      if command_info
        STDOUT.write(command_info[:result])
        exit_status = command_info[:exit_status] if command_info[:exit_status]
      end

      exit(exit_status)
    end
  end
end
