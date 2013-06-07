# coding: UTF-8

require "spec_helper"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"

require "warden/container/linux"

describe "linux", :platform => "linux", :needs_root => true do
  let(:work_path) { File.join(Dir.tmpdir, "warden", "spec") }
  let(:unix_domain_path) { File.join(work_path, "warden.sock") }
  let(:container_klass) { "Warden::Container::Linux" }
  let(:container_rootfs_path) { File.join(work_path, "..", "rootfs") }
  let(:container_depot_path) { File.join(work_path, "containers") }
  let(:container_depot_file) { container_depot_path + ".img" }
  let(:have_uid_support) { true }
  let(:netmask) { Warden::Network::Netmask.new(255, 255, 255, 252) }
  let(:allow_networks) { [] }
  let(:deny_networks) { [] }

  before do
    FileUtils.mkdir_p(work_path)

    unless File.directory?(container_rootfs_path)
      raise "%s does not exist" % container_rootfs_path
    end

    FileUtils.mkdir_p(container_depot_path)

    execute("dd if=/dev/null of=#{container_depot_file} bs=1M seek=100 1> /dev/null 2> /dev/null")

    execute("mkfs.ext4 -b 4096 -q -F -O ^has_journal,uninit_bg #{container_depot_file}")
    execute("losetup --all | grep #{container_depot_file} | cut --delimiter=: --fields=1 | xargs --no-run-if-empty --max-args=1 losetup --detach")
    execute("losetup --find #{container_depot_file}")
    @loop_device = execute("losetup --all | grep #{container_depot_file} | cut --delimiter=: --fields=1").strip

    execute("mount #{@loop_device} #{container_depot_path}")

    start_warden
  end

  after do
    stop_warden

    # Destroy all artifacts
    Dir[File.join(Warden::Util.path("root"), "*", "clear.sh")].each do |clear|
      execute("#{clear} #{container_depot_path} > /dev/null")
    end

    unmount_depot

    execute("rmdir #{container_depot_path}")
    execute("rm #{container_depot_file}")

    execute("losetup --all | grep #{container_depot_file} | cut --delimiter=: --fields=1 | xargs --no-run-if-empty --max-args=1 losetup --detach")
  end

  def execute(command)
    `#{command}`.tap do
      $?.should be_success
    end
  end

  def unmount_depot(tries = 100)
    out = execute("umount #{container_depot_path} 2>&1")
    raise "Failed unmounting #{container_depot_path}: #{out}" unless $?.success?
  rescue
    tries -= 1
    if tries > 0
      raise
    else
      sleep 0.01
      retry
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
    @start_address = next_class_c.to_human

    @pid = fork do
      Process.setsid
      Signal.trap("TERM") { exit }

      Warden::Server.setup(
        "server" => {
          "unix_domain_path" => unix_domain_path,
          "container_klass" => container_klass,
          "container_rootfs_path" => container_rootfs_path,
          "container_depot_path" => container_depot_path,
          "container_grace_time" => 5,
          "job_output_limit" => 100 * 1024 },
        "network" => {
          "pool_start_address" => @start_address,
          "pool_size" => 64,
          "allow_networks" => allow_networks,
          "deny_networks" => deny_networks },
        "port" => {
          "pool_start_port" => 64000,
          "pool_size" => 1000 },
        "logging" => {
          "level" => "debug",
          "file" => File.join(work_path, "warden.log") }
      )

      Warden::Server.run!
    end

    # Wait for the socket to come up
    loop do
      begin
        UNIXSocket.new(unix_domain_path)
        break
      rescue Errno::ENOENT, Errno::ECONNREFUSED
      end

      if Process.waitpid(@pid, Process::WNOHANG)
        STDERR.puts "Warden exited early aborting spec suite"
        exit 1
      end

      sleep 0.01
    end
  end

  def stop_warden(signal = "USR2")
    Process.kill(signal, -@pid) rescue Errno::ECHILD
    Process.waitpid(@pid) rescue Errno::ECHILD
  end

  def restart_warden(signal = "USR2")
    stop_warden(signal)
    start_warden
  end

  def client
    @client ||= create_client
  end

  def reset_client
    @client = nil
  end

  it_should_behave_like "lifecycle"
  it_should_behave_like "running commands"
  it_should_behave_like "info"
  it_should_behave_like "file transfer"
  it_should_behave_like "drain"
  it_should_behave_like "snapshotting_common"
  it_should_behave_like "snapshotting_net_in"

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

    def trigger_oom
      # Allocate 20MB, this should OOM and cause the container to be torn down
      run "perl -e 'for ($i = 0; $i < 20; $i++ ) { $foo .= \"A\" x (1024 * 1024); }'"

      # Wait a bit for the warden to be notified of the OOM
      sleep 0.01
    end

    before do
      @handle = client.create.handle
    end

    it "should default to a large number" do
      response = limit_memory
      response.limit_in_bytes.should == 9223372036854775807
    end

    describe "setting limits" do
      def integer_from_memory_cgroup(file)
        File.read(File.join("/tmp/warden/cgroup/memory", "instance-#{@handle}", file)).to_i
      end

      let(:hundred_mb) { 100 * 1024 * 1024 }

      before do
        response = limit_memory(:limit_in_bytes => hundred_mb)
        response.limit_in_bytes.should == hundred_mb
      end

      it "sets `memory.limit_in_bytes`" do
        integer_from_memory_cgroup("memory.limit_in_bytes").should == hundred_mb
      end

      it "sets `memory.memsw.limit_in_bytes`" do
        integer_from_memory_cgroup("memory.memsw.limit_in_bytes").should == hundred_mb
      end

      describe "increasing limits" do
        before do
          response = limit_memory(:limit_in_bytes => 2 * hundred_mb)
          response.limit_in_bytes.should == 2 * hundred_mb
        end

        it "sets `memory.limit_in_bytes`" do
          integer_from_memory_cgroup("memory.limit_in_bytes").should == 2 * hundred_mb
        end

        it "sets `memory.memsw.limit_in_bytes`" do
          integer_from_memory_cgroup("memory.memsw.limit_in_bytes").should == 2 * hundred_mb
        end
      end
    end

    def self.it_should_stop_container_when_an_oom_event_occurs
      it "should stop container when an oom event occurs" do
        trigger_oom

        response = client.info(:handle => handle)
        response.state.should == "stopped"
        response.events.should include("oom")
      end
    end

    context "before restart" do
      before do
        limit_memory(:limit_in_bytes => 10 * 1024 * 1024)
      end

      it_should_stop_container_when_an_oom_event_occurs
    end

    context "after restart" do
      before do
        limit_memory(:limit_in_bytes => 10 * 1024 * 1024)
        restart_warden
        reset_client
      end

      it_should_stop_container_when_an_oom_event_occurs
    end

    context "after kill" do
      before do
        limit_memory(:limit_in_bytes => 10 * 1024 * 1024)
        restart_warden(:KILL)
        reset_client
      end

      it_should_stop_container_when_an_oom_event_occurs
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

    context "with a 2M disk limit" do
      before do
        limit_disk(:byte_limit => 2 * 1024 * 1024)
      end

      it "should succeed to write a 1M file" do
        response = run("dd if=/dev/zero of=/tmp/test bs=1M count=1")
        response.exit_status.should == 0
      end

      it "should fail to write a 4M file" do
        response = run("dd if=/dev/zero of=/tmp/test bs=1M count=4")
        response.exit_status.should == 1
        response.stderr.should =~ /quota exceeded/i
      end
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

  describe "net_out" do
    def net_out(options = {})
      response = client.net_out(options)
      response.should be_ok
      response
    end

    def run(handle, script)
      response = client.run(:handle => handle, :script => script)
      response.should be_ok
      response
    end

    def reachable?(handle, ip)
      response = run(handle, "ping -q -W 1 -c 1 #{ip}")
      response.stdout =~ /\b(\d+) received\b/i
      $1.to_i > 0
    end

    context "reachability" do
      # Allow traffic to the first two subnets
      let(:allow_networks) do
        ["4.2.2.1/32"]
      end

      # Deny traffic to everywhere else
      let(:deny_networks) do
        ["0.0.0.0/0"]
      end

      before do
        @containers = 3.times.map do
          handle = client.create.handle
          { :handle => handle, :ip => client.info(:handle => handle).container_ip }
        end
      end

      it "reaches every container from the host" do
        @containers.each do |e|
          `ping -q -w 1 -c 1 #{e[:ip]}` =~ /\b(\d+) received\b/i
          $1.to_i.should == 1
        end
      end

      it "allows traffic to networks configured in allowed networks" do
        reachable?(@containers[0][:handle], "4.2.2.1").should be_true
        reachable?(@containers[1][:handle], "4.2.2.1").should be_true
        reachable?(@containers[2][:handle], "4.2.2.1").should be_true
      end

      it "does not allow traffic to networks not configured in allowed networks" do
        [0, 1, 2].permutation(2) do |first, second|
          reachable?(@containers[first][:handle], @containers[second][:ip]).should be_false
        end
      end

      it "allows traffic to networks after net_out" do
        net_out(:handle => @containers[0][:handle], :network => @containers[2][:ip])
        reachable?(@containers[0][:handle], @containers[2][:ip]).should be_true
        net_out(:handle => @containers[2][:handle], :network => @containers[0][:ip])
        reachable?(@containers[2][:handle], @containers[0][:ip]).should be_true
      end
    end

    describe "check network and port fields" do
      let(:handle) { client.create.handle }

      it "should raise error when both fields are absent" do
        expect do
          net_out(:handle => handle)
        end.to raise_error(Warden::Client::ServerError, %r"specify network and/or port"i)
      end

      it "should not raise error when network field is present" do
        net_out(:handle => handle, :network => "4.2.2.2").should be_ok
      end

      it "should not raise error when port field is present" do
        net_out(:handle => handle, :port => 1234).should be_ok
      end

      it "should not raise error when both network and port fields are present" do
        net_out(:handle => handle, :network => "4.2.2.2", :port => 1234).should be_ok
      end
    end
  end

  describe "net_in" do
    attr_reader :handle

    def net_in(options = {})
      response = client.net_in(options.merge(:handle => handle))
      response.should be_ok
      response
    end

    before(:all) do
      ["/", container_rootfs_path].each do |root|
        paths = %w(/bin /usr/bin).map { |e| File.join(root, e) }
        if !paths.any? { |e| File.exist?(File.join(e, "nc")) }
          raise "Expected `nc` to be present in [#{paths.join(", ")}]"
        end
      end
    end

    before do
      @handle = client.create.handle
    end

    def attempt(n = 10, s = 0.1, &blk)
      n.times do
        return if blk.call
        sleep(s)
      end

      raise "Failed after #{n} attempts to run #{blk.inspect}"
    end

    def check_mapping(response)
      # Verify that the port mapping in @ports works
      script = "echo ok | nc -l #{response.container_port}"
      job_id = client.spawn(:handle => handle,
                            :script => script).job_id

      # Connect via external IP
      external_ip = `ip route get 1.1.1.1`.split(/\n/).first.split(/\s+/).last

      # Connect through nc
      attempt do
        `echo | nc #{external_ip} #{response.host_port}`.chomp == "ok"
      end

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

    it "should include list of ids of jobs that are alive" do
      response = client.spawn(:handle => handle,
                              :script => "sleep 2; id -u")
      job_id_1 = response.job_id

      response = client.spawn(:handle => handle,
                              :script => "id -u")
      job_id_2 = response.job_id

      sleep 0.1

      response = client.info(:handle => handle)
      response.job_ids.should == [job_id_1]
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

    it "should return an error when a bind mount does not exist" do
      @bind_mount.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO
      @bind_mount.src_path = tmpdir + ".doesnt.exist"

      expect do
        create
      end.to raise_error(Warden::Client::ServerError, /\bdoes not exist\b/i)
    end
  end

  describe "create with network" do
    it "should be able to specify network" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = @start_address

      response = client.call(create_request)
      response.should be_ok

      info_request = Warden::Protocol::InfoRequest.new
      info_request.handle = response.handle

      response = client.call(info_request)
      network = Warden::Network::Address.new(response.container_ip).network(netmask)

      network.to_human.should == @start_address
    end

    it "should raise error to use network not in the pool" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = '1.1.1.1'

      expect {
        response = client.call(create_request)
      }.to raise_error Warden::Client::ServerError
    end
  end

  describe "create with rootfs" do
    let(:another_rootfs_path) { File.join(work_path, "rootfs2") }
    let(:bad_rootfs_path) { File.join(work_path, "bad_rootfs") }

    before do
      unless File.exist? another_rootfs_path
        FileUtils.ln_s(container_rootfs_path, another_rootfs_path)
      end
    end

    it "should be able to use another rootfs" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.rootfs = another_rootfs_path

      response = client.call(create_request)
      response.should be_ok
    end

    it "should raise error on bad rootfs path" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.rootfs = bad_rootfs_path

      expect {
        response = client.call(create_request)
      }.to raise_error Warden::Client::ServerError
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

  describe "resource limits" do
    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    it "should be configurable" do
      rlimits = Warden::Protocol::ResourceLimits.new(:nofile => 1234)
      response = client.run(:handle => handle, :script => "ulimit -n", :rlimits => rlimits)
      response.exit_status.should == 0
      response.stdout.chomp.should == "1234"
      response.stderr.chomp.should == ""
    end
  end

  describe "recovery" do
    before do
      @h1 = client.create.handle
      @h2 = client.create.handle

      stop_warden(:KILL)
    end

    after do
      start_warden

      reset_client

      containers = client.list.handles
      containers.should_not include(@h1)
      containers.should include(@h2)

      # Test that the path for h1 is gone
      h1_path = File.join(container_depot_path, @h1)
      File.directory?(h1_path).should be_false
    end

    it "should destroy containers without snapshot" do
      snapshot_path = File.join(container_depot_path, @h1, "snapshot.json")
      File.exist?(snapshot_path).should be_true
      File.delete(snapshot_path)
    end

    it "should destroy containers that have stopped" do
      wshd_pid_path = File.join(container_depot_path, @h1, "run", "wshd.pid")
      File.exist?(wshd_pid_path).should be_true
      Process.kill("KILL", File.read(wshd_pid_path).to_i)
    end
  end
end
