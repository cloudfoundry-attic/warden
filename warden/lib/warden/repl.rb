# coding: UTF-8

require "json"
require "pp"
require "readline"
require "shellwords"
require "warden/client"

module Warden
  class Repl

    COMMAND_LIST = ['ping', 'create', 'stop', 'destroy', 'spawn', 'link',
                    'stream', 'run', 'net', 'limit', 'info', 'list','copy',
                    'help']

    HELP_MESSAGE =<<-EOT
ping                          - ping warden
create [OPTION OPTION ...]    - create container, optionally pass options.
destroy <handle>              - shutdown container <handle>
stop <handle>                 - stop all processes in <handle>
spawn <handle> cmd            - spawns cmd inside container <handle>, returns #jobid
link <handle> #jobid          - do blocking read on results from #jobid
stream <handle> #jobid        - do blocking stream on results from #jobid
run <handle>  cmd             - short hand for stream(spawn(cmd)) i.e. spawns cmd, streams the result
list                          - list containers
info <handle>                 - show metadata for container <handle>
limit <handle> mem  [<value>] - set or get the memory limit for the container (in bytes)
limit <handle> bandwidth <rate> <bandwidth> - set the bandwidth limit for the container <rate> is the maxium transfer rate for both outbound and inbound(in bytes/sec) <burst> is the burst size(in bytes)
net <handle> #in              - forward port #in on external interface to container <handle>
net <handle> #out <address[/mask][:port]> - allow traffic from the container <handle> to address <address>
copy <handle> <in|out> <src path> <dst path> [ownership opts] - Copy files/directories in and out of the container
help                          - show help message

---

The OPTION argument for `create` can be one of:
  * bind_mount:HOST_PATH,CONTAINER_PATH,ro|rw
      e.g. create bind_mount:/tmp/,/home/vcap/tmp,ro
  * grace_time:SECONDS
      e.g. create grace_time:300

Please see README.md for more details.
EOT

    def initialize(opts={})
      @trace = opts[:trace] == true
      @warden_socket_path = opts[:warden_socket_path] || "/tmp/warden.sock"
      @client = Warden::Client.new(@warden_socket_path)
      @history_path = opts[:history_path] || File.join(ENV['HOME'], '.warden-history')
    end

    def start
      restore_history

      @client.connect unless @client.connected?

      comp = proc { |s|
        if s[0] == '0'
          container_list.grep( /^#{Regexp.escape(s)}/ )
        else
          COMMAND_LIST.grep( /^#{Regexp.escape(s)}/ )
        end
      }

      Readline.completion_append_character = " "
      Readline.completion_proc = comp

      while line = Readline.readline('warden> ', true)
        if process_line(line)
          save_history
        end
      end
    end

    def container_list
      @client.write(['list'])
      JSON.parse(@client.read.inspect)
    end

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

    def make_create_config(args)
      config = {}

      return config if args.nil?

      args.each do |arg|
        head, tail = arg.split(":", 2)

        case head
        when "bind_mount"
          src, dst, mode = tail.split(",")
          config["bind_mounts"] ||= []
          config["bind_mounts"].push [src, dst, { "mode" => mode }]
        when "grace_time"
          config["grace_time"] = tail
        when "disk_size_mb"
          # Deprecated
        else
          raise "Unknown argument: #{head}"
        end
      end

      config
    end

    def create(args)
      args = ['create', make_create_config(args)]
      container = talk_to_warden(args)
      puts container

      container
    end

    def link(args)
      args.unshift('link')
      exit_status, stdout, stderr = talk_to_warden(args)

      puts "exit status: #{exit_status}"
      puts
      puts "stdout:"
      puts stdout
      puts
      puts "stderr:"
      puts stderr
      puts

      [exit_status, stdout, stderr]
    end

    def spawn(args, print = true)
      if args.size > 2
        tail = args.slice!(1..-1)
        args.push(tail.join(' '))
      end

      args.unshift('spawn')
      job_id = talk_to_warden(args)
      puts job_id if print

      job_id
    end

    def stream(args)
      args.unshift('stream')
      name, data, exit_status = talk_to_warden(args)
      while exit_status.nil?
        if name.downcase == "stdout"
          STDOUT.write(data)
        else
          STDERR.write(data)
        end

        name, data, exit_status = @client.read
      end

      exit_status
    end

    def help(args)
      puts HELP_MESSAGE
      nil
    end

    def run(args)
      container = args[0]
      job_id = spawn(args, false)
      stream([container, job_id])
    end

    def talk_to_warden(args)
      @client.connect() unless @client.connected?
      @client.write(args)
      @client.read
    end

    def process_line(line)
      words = Shellwords.shellwords(line)
      return nil if words.empty?

      puts "+ #{line}" if @trace

      args = words.slice(1..-1)
      command_info = {
        :name   => words[0],
        :args => args
      }

      begin
        result = nil
        if respond_to? words[0].to_sym
          result = send(words[0].to_sym, args)
        else
          result = talk_to_warden(words)
          pp result
        end
        command_info[:result] = result
      rescue => e
        command_info[:error] = e
        if e.message.match('unknown command')
          puts "#{e.message}, try help for assistance."
        else
          puts e.message
        end
      end

      command_info
    end
  end
end
