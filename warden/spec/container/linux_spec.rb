# coding: UTF-8

require "spec_helper"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"

require "warden/container/linux"

def next_class_c
  $class_c ||= Warden::Network::Address.new("172.16.0.0")

  rv = $class_c
  $class_c = $class_c + 256
  rv
end

describe "linux", :platform => "linux", :needs_root => true do
  let!(:unix_domain_path) { Warden::Util.path("tmp/warden.sock") }
  let!(:container_klass) { "Warden::Container::Linux" }
  let!(:container_depot_path) { Dir.mktmpdir(nil, Warden::Util.path("tmp")) }
  let!(:container_depot_file) { container_depot_path + ".img" }
  let (:have_uid_support) { true }

  before do
    `dd if=/dev/null of=#{container_depot_file} bs=1M seek=100 1> /dev/null 2> /dev/null`
    $?.should be_success

    features  = []
    features << "^has_journal" # don't include a journal
    features << "uninit_bg"    # skip initialization of block groups

    `mkfs.ext4 -q -F -O #{features.join(",")} #{container_depot_file}`
    $?.should be_success

    `mount -o loop #{container_depot_file} #{container_depot_path}`
    $?.should be_success
  end

  after do
    tries = 0

    begin
      out = `umount #{container_depot_path} 2>&1`
      raise "Failed unmounting #{container_depot_path}: #{out}" unless $?.success?
    rescue
      tries += 1
      if tries >= 100
        raise
      else
        sleep 0.01
        retry
      end
    end

    `rmdir #{container_depot_path}`
    $?.should be_success

    `rm #{container_depot_file}`
    $?.should be_success
  end

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

  def create_client
    client = ::Warden::Client.new(unix_domain_path)
    client.connect
    client
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

  let(:client) { create_client }

  it_should_behave_like "lifecycle"
  it_should_behave_like "running commands"
  it_should_behave_like "streaming commands"
  it_should_behave_like "info"
  it_should_behave_like "file transfer"
  it_should_behave_like "drain"

  describe "limit_memory" do
    attr_reader :handle

    def limit_memory(options = {})
      response = client.limit_memory(options.merge(:handle => handle))
      response.should be_ok
      response
    end

    def run(script)
      response = client.run(:handle => handle, :script => script)
      response.should be_ok
      response
    end

    before do
      @handle = client.create.handle
    end

    it "should default to a large number" do
      response = limit_memory
      response.limit_in_bytes.should == 9223372036854775807
    end

    it "sets `memory.limit_in_bytes` in the correct cgroup" do
      hund_mb = 100 * 1024 * 1024
      response = limit_memory(:limit_in_bytes => hund_mb)
      response.limit_in_bytes.should == hund_mb

      raw_lim = File.read(File.join("/sys/fs/cgroup/memory", "instance-#{@handle}", "memory.limit_in_bytes"))
      raw_lim.to_i.should == hund_mb
    end

    it "stops containers when an oom event occurs" do
      usage = File.read(File.join("/sys/fs/cgroup/memory", "instance-#{@handle}", "memory.usage_in_bytes"))
      limit_memory(:limit_in_bytes => usage.to_i + 10 * 1024 * 1024)

      # Allocate 20MB, this should OOM and cause the container to be torn down
      run "perl -e 'for ($i = 0; $i < 20; $i++ ) { $foo .= \"A\" x (1024 * 1024); }'"

      # Wait a bit for the warden to be notified of the OOM
      sleep 0.01

      response = client.info(:handle => handle)
      response.state.should == "stopped"
      response.events.should include("oom")
    end
  end

  describe "limit_disk" do
    attr_reader :handle

    def limit_disk(options = {})
      response = client.limit_disk(options.merge(:handle => handle))
      response.should be_ok
      response
    end

    def run(script)
      response = client.run(:handle => handle, :script => script)
      response.should be_ok
      response
    end

    before do
      @handle = client.create.handle
    end

    it "should allow the disk quota to be changed" do
      response = limit_disk(:block_limit => 12345)
      response.block_limit.should == 12345
    end

    it "should set the block quota to 0 on creation" do
      # When every test is run in full isolation and even the file
      # system is recreated, this is impossible to test unless we create
      # and destroy containers until we have exhausted the UID pool and
      # re-use an UID for the first time. The test is kept as a reminder.
      response = limit_disk()
      response.block_limit.should == 0
    end

    it "should enforce the quota" do
      limit_disk(:byte_limit => 2 * 1024 * 1024)

      response = run("dd if=/dev/zero of=/tmp/test bs=1MB count=4")
      response.exit_status.should == 1
      response.stderr.should =~ /quota exceeded/i
    end
  end

  describe "limit_bandwidth" do
    attr_reader :handle

    def limit_bandwidth(options = {})
      response = client.limit_bandwidth(options.merge(:handle => handle))
      response.should be_ok
      response
    end

    before do
      @handle = client.create.handle
    end

    it "should set the bandwidth" do
      response = limit_bandwidth(:rate => 100 * 1000, :burst => 1000)
      ret = client.info(:handle => handle)
      [ret.bandwidth_stat.in_rate, ret.bandwidth_stat.out_rate].each do |v|
        v.should == 100 * 1000
      end
      [ret.bandwidth_stat.in_burst, ret.bandwidth_stat.out_burst].each do |v|
        v.should == 1000
      end
    end

    it "should allow bandwidth to be changed" do
      response = limit_bandwidth(:rate => 200 * 1000, :burst => 2000)
      ret = client.info(:handle => handle)
      [ret.bandwidth_stat.in_rate, ret.bandwidth_stat.out_rate].each do |v|
        v.should == 200 * 1000
      end
      [ret.bandwidth_stat.in_burst, ret.bandwidth_stat.out_burst].each do |v|
        v.should == 2000
      end
    end
  end

  describe "net_out", :netfilter => true do
    attr_reader :handle

    def net_out(options = {})
      response = client.net_out(options.merge(:handle => handle))
      response.should be_ok
      response
    end

    def run(script)
      response = client.run(:handle => handle, :script => script)
      response.should be_ok
      response
    end

    def reachable?(ip)
      response = run "ping -q -W 1 -c 1 #{ip}"
      response.stdout =~ /\b(\d+) received\b/i
      $1.to_i > 0
    end

    before do
      @handle = client.create.handle
    end

    describe "to denied range" do
      before do
        # Make sure the host can reach an ip in the denied range
        `ping -q -w 1 -c 1 4.2.2.2` =~ /\b(\d+) received\b/i
        $1.to_i.should == 1
      end

      it "should deny traffic" do
        reachable?("4.2.2.2").should be_false
      end

      it "should allow traffic after explicitly allowing it" do
        net_out(:network => "4.2.2.2")
        reachable?("4.2.2.2").should be_true
      end
    end

    describe "to allowed range" do
      it "should allow traffic" do
        reachable?("4.2.2.3").should be_true
      end
    end

    describe "to other range" do
      it "should allow traffic" do
        reachable?("8.8.8.8").should be_true
      end
    end
  end

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
      script = "echo ok | nc -l #{response.container_port}"
      job_id = client.spawn(:handle => handle,
                            :script => script).job_id

      # Give nc some time to start
      sleep 0.2

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

    it "should allow the port on the container side to be specified" do
      response = net_in(:container_port => 8080)
      response.container_port.should == 8080
      check_mapping(response)
    end

    it "should allow the port on the host side to be specified" do
      response = net_in(:host_port => 8080)
      response.host_port.should == 8080
      response.container_port.should == 8080
      check_mapping(response)
    end

    it "should allow the port on both of the container and host sides to be specified" do
      response = net_in(:host_port => 8080, :container_port => 8081)
      response.host_port.should == 8080
      response.container_port.should == 8081
      check_mapping(response)
    end
  end

  describe "info" do
    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    it "should include memory stat" do
      response = client.info(:handle => handle)
      response.memory_stat.rss.should > 0
    end

    it "should include cpu stat" do
      response = client.info(:handle => handle)
      response.cpu_stat.usage.should > 0
      response.cpu_stat.user.should >= 0
      response.cpu_stat.system.should >= 0
    end

    it "should include disk stat" do
      response = client.info(:handle => handle)
      response.disk_stat.inodes_used.should > 0
      bytes_used = response.disk_stat.bytes_used
      bytes_used.should > 0

      response = client.run(:handle => handle,
                            :script => "dd if=/dev/urandom of=/tmp/foo bs=1MB count=1")
      response.exit_status.should == 0

      response = client.info(:handle => handle)
      response.disk_stat.bytes_used.should be_within(32000).of(bytes_used + 1_000_000)
    end

    it "should include bandwidth stat" do
      response = client.info(:handle => handle)
      [response.bandwidth_stat.in_rate, response.bandwidth_stat.out_rate].each do |x|
        x.should >= 0
      end
      [response.bandwidth_stat.in_burst, response.bandwidth_stat.out_burst].each do |x|
        x.should >= 0
      end
    end
  end

  describe "bind mounts" do
    attr_reader :handle

    let(:tmpdir) { Dir.mktmpdir }
    let(:test_basename) { "test" }
    let(:test_path) { File.join(tmpdir, test_basename) }
    let(:test_contents) { "testing123" }

    def run(script)
      response = client.run(:handle => handle, :script => script)
      response.should be_ok
      response
    end

    def create
      response = client.call(@create_request)
      response.should be_ok

      @handle = response.handle
    end

    before do
      File.open(test_path, "w+") { |f| f.write(test_contents) }

      FileUtils.chmod_R(0777, tmpdir)

      @bind_mount = Warden::Protocol::CreateRequest::BindMount.new
      @bind_mount.src_path = tmpdir
      @bind_mount.dst_path = "/tmp/bind_mounted"

      @create_request = Warden::Protocol::CreateRequest.new
      @create_request.bind_mounts = [@bind_mount]
    end

    after do
      # Mounts should not appear in /etc/mtab
      File.read("/etc/mtab").should_not match(Regexp.escape(@bind_mount.src_path))
    end

    after :each do
      FileUtils.rm_rf(tmpdir)
    end

    it "should support bind mounting in RO mode" do
      @bind_mount.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO
      create

      # Make sure we CAN READ a file that already exists
      response = run "cat #{@bind_mount.dst_path}/#{test_basename}"
      response.exit_status.should == 0
      response.stdout.should == test_contents

      # Make sure we CAN'T WRITE a file
      response = run "touch #{@bind_mount.dst_path}/test"
      response.exit_status.should == 1
      response.stdout.should be_empty
      response.stderr.should match(/read-only file system/i)
    end

    it "should support bind mounting in RW mode" do
      @bind_mount.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RW
      create

      # Make sure we CAN READ a file that already exists
      response = run "cat #{@bind_mount.dst_path}/#{test_basename}"
      response.exit_status.should == 0
      response.stdout.should == test_contents

      # Make sure we CAN WRITE a file
      response = run "touch #{@bind_mount.dst_path}/test"
      response.exit_status.should == 0
      response.stdout.should be_empty
      response.stderr.should be_empty
    end
  end

  describe "run with privileged flag" do
    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    it "should run commands as root if the privileged option is set" do
      response = client.run(:handle => handle, :script => "id -u", :privileged => true)
      response.exit_status.should == 0
      response.stdout.should == "0\n"
      response.stderr.should == ""
    end
  end
end

