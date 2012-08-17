require "optparse"
require "warden/repl_v2"
require "warden/commands_manager"

module Warden
  class ReplRunner

    # Parses command-line arguments, runs Repl and handles the output and exit
    # status of commands.
    #
    # Parameters:
    # - args [Array of Strings]:
    #      Command-line arguments to be parsed.
    def self.run(args = [])
      exit_on_error = false
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
              "Only applicable in non-interactive mode. If a multi-command string" \
              + " is supplied, exit after the first unsuccessful command.") do
          exit_on_error = true
        end

        op.on_tail("--help", "Show help.") do
          puts op
          puts
          puts "[commands] can be one of the following separated by a newline."
          puts Warden::Repl.new.describe_commands(op.summary_width - 3)
          puts
          exit
        end
      end

      global_args = []
      commands = ""
      delimiter_found = false
      args.each do |element|
        element = element.dup
        if element == "--"
          raise "Delimiter: '--' specified multiple times." if delimiter_found
          delimiter_found = true
        else
          if delimiter_found
            commands << " " unless commands.empty?
            commands << element
          else
            global_args << element
          end
        end
      end

      opt_parser.parse(global_args)
      repl = Warden::Repl.new(options)

      unless commands.empty?
        exit_status = 0

        commands.split("\n").each do |command|
          command_info = nil
          command = command.strip

          unless command.empty?
            begin
              command_info = repl.process_line(command) unless command.empty?
            rescue Warden::CommandsManager::CommandError => ce
              STDERR.write("#{ce}\n")
              ce.backtrace.each { |err| STDERR.write("#{err}\n") }
              Process.exit(1) if exit_on_error
            end

            exit_status = 0
            if command_info
              STDOUT.write(command_info[:result])
              exit_status = command_info[:exit_status] if command_info[:exit_status]
            end

            break if (exit_status != 0) && exit_on_error
          end
        end

        exit(exit_status)
      else
        trap('INT') do
          STDERR.write("\n\nExiting...\n")
          exit
        end

        repl.start
      end
    end
  end
end
