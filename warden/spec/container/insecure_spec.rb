# coding: UTF-8

require "spec_helper"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"

require "warden/container/insecure"

def next_class_c
  $class_c ||= Warden::Network::Address.new("172.16.0.0")

  rv = $class_c
  $class_c = $class_c + 256
  rv
end

describe "insecure" do
  let!(:unix_domain_path) { Warden::Util.path("tmp/warden.sock") }
  let!(:container_klass) { "Warden::Container::Insecure" }
  let!(:container_depot_path) { Dir.mktmpdir(nil, Warden::Util.path("tmp")) }
  let!(:container_depot_file) { container_depot_path + ".img" }
  let(:have_uid_support) { false }

  before do
    start_warden
  end

  after do
    `kill -9 -#{@pid}`
    Process.waitpid(@pid)

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
          "container_grace_time" => 5 },
        "network" => {
          "pool_start_address" => start_address,
          "pool_size" => 64,
          "allow_networks" => ["4.2.2.3/32"],
          "deny_networks" => ["4.2.2.0/24"] },
        "logging" => {
          "level" => "debug",
          "file" => Warden::Util.path("tmp/warden.log") }

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

  def create_client
    client = ::Warden::Client.new(unix_domain_path)
    client.connect
    client
  end

  let(:client) { create_client }

  it_should_behave_like "lifecycle"
  it_should_behave_like "running commands"
  it_should_behave_like "streaming commands"
  it_should_behave_like "info"
  it_should_behave_like "file transfer"
  it_should_behave_like "drain"

  describe "net_in", :netfilter => true do
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
      `nc #{external_ip} #{response.host_port}`.chomp.should == "ok"

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
