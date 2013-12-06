# coding: UTF-8

require "spec_helper"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"

require "warden/container/insecure"

describe "insecure" do
  let(:work_path) { File.join(Dir.tmpdir, "warden", "spec") }
  let(:unix_domain_path) { File.join(work_path, "warden.sock") }
  let(:container_klass) { "Warden::Container::Insecure" }
  let(:container_depot_path) { File.join(work_path, "containers") }
  let(:container_depot_file) { container_depot_path + ".img" }
  let(:have_uid_support) { false }
  let(:server_pidfile) { nil }
  let(:syslog_socket) { nil }

  before do
    FileUtils.mkdir_p(container_depot_path)
  end

  before do
    start_warden
  end

  after do
    stop_warden

    # Destroy all artifacts
    Dir[File.join(Warden::Util.path("root"), "*", "clear.sh")].each do |clear|
      `#{clear} #{container_depot_path} > /dev/null`
    end
  end

  def start_warden
    FileUtils.rm_f(unix_domain_path)

    # Grab new network for every test to avoid resource contention
    start_address = next_class_c.to_human

    @pid = fork do
      Process.setsid
      Signal.trap("TERM") { exit }

      Warden::Server.setup \
        "server" => {
          "unix_domain_path" => unix_domain_path,
          "container_klass" => container_klass,
          "container_depot_path" => container_depot_path,
          "container_grace_time" => 5,
          "job_output_limit" => 100 * 1024,
          "pidfile" => server_pidfile,
          "syslog_socket" => syslog_socket },
        "network" => {
          "pool_start_address" => start_address,
          "pool_size" => 64,
          "allow_networks" => ["4.2.2.3/32"],
          "deny_networks" => ["4.2.2.0/24"] },
        "port" => {
          "pool_start_port" => 64000,
          "pool_size" => 1000 },
        "logging" => {
          "level" => "debug",
          "file" => File.join(work_path, "warden.log") }

      Warden::Server.run!
    end

    # Wait for the socket to come up
    until File.exist?(unix_domain_path)
      if Process.waitpid(@pid, Process::WNOHANG)
        STDERR.puts "Warden process exited before socket was up; aborting spec suite."
        exit 1
      end

      sleep 0.01
    end
  end

  def stop_warden(signal = "USR2")
    Process.kill(signal, -@pid) rescue Errno::ECHILD
    Process.waitpid(@pid) rescue Errno::ECHILD
  end

  def create_client
    client = ::Warden::Client.new(unix_domain_path)
    client.connect
    client
  end

  def client
    @client ||= create_client
  end

  it_should_behave_like "lifecycle"
  it_should_behave_like "running commands"
  it_should_behave_like "info"
  it_should_behave_like "file transfer"
  it_should_behave_like "drain"
  it_should_behave_like "snapshotting_common"
  it_should_behave_like "writing_pidfile"

  describe "net_in" do
    attr_reader :handle

    def net_in(options = {})
      response = client.net_in(options.merge(:handle => handle))
      response.should be_ok
      response
    end

    before do
      @handle = client.create.handle
    end

    def check_mapping(response)
      # Verify that the port mapping in @ports works
      job_id = client.spawn(:handle => handle, :script => "echo ok | nc -l #{response.container_port}").job_id

      # Give nc some time to start
      sleep 0.1

      # Connect via external IP
      external_ip = `ip route get 1.1.1.1`.split(/\n/).first.split(/\s+/).last

      # Pipe echo to give nc a stdin (it quits immediately after connecting if it doesn't have a stdin)
      `echo | nc #{external_ip} #{response.host_port}`.chomp.should == "ok"

      # Clean up
      client.link(:handle => handle, :job_id => job_id)
    end

    it "should work" do
      response = net_in()
      check_mapping(response)
    end

    it "should ignore the port on the container side if specified" do
      response = net_in(:container_port => 1234)
      response.container_port.should_not == 1234
      check_mapping(response)
    end
  end
end
