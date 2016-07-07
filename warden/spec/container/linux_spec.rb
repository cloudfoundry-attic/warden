# coding: UTF-8

require "spec_helper"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"
require "ipaddr"
require "socket"

require "warden/container/linux"

describe "linux", :platform => "linux", :needs_root => true do
  include Helpers::Drain

  attr_reader :container_rootfs_path, :work_path

  let(:unix_domain_path) { File.join(work_path, "warden.sock") }
  let(:container_klass) { "Warden::Container::Linux" }
  let(:container_depot_path) { File.join(work_path, "containers") }
  let(:container_depot_file) { container_depot_path + ".img" }
  let(:have_uid_support) { true }
  let(:netmask) { Warden::Network::Netmask.new(255, 255, 255, 252) }
  let(:allow_networks) { [] }
  let(:allow_host_access) { false }
  let(:mtu) { 1500 }
  let(:job_output_limit) { 100 * 1024 }
  let(:server_pidfile) { nil }
  let(:syslog_socket) { nil }
  let(:lang) { ENV['LANG'] }

  before(:all) do
    @work_path = File.join(Dir.tmpdir, "warden", "spec")
    @container_rootfs_path = File.join(work_path, "..", "rootfs")
  end

  let(:dns_servers) { [] }

  before do
    FileUtils.mkdir_p(work_path)

    unless File.directory?(container_rootfs_path)
      raise "%s does not exist" % container_rootfs_path
    end

    FileUtils.mkdir_p(container_depot_path)

    execute("dd if=/dev/null of=#{container_depot_file} bs=1M seek=100 1> /dev/null 2> /dev/null")

    execute("mkfs.ext4 -b 4096 -q -F -O ^has_journal,uninit_bg #{container_depot_file}")
    execute("losetup --all | grep #{container_depot_file} | cut --delimiter=: --fields=1 | xargs --no-run-if-empty --max-args=1 losetup --detach")
    @loop_device = execute("losetup -f").strip
    execute("losetup #{@loop_device} #{container_depot_file}")
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
    execute("sync")

    execute("losetup --all | grep #{container_depot_file} | cut --delimiter=: --fields=1 | xargs --no-run-if-empty --max-args=1 losetup --detach")
    execute("rm #{container_depot_file}")
  end

  def execute(command)
    `#{command}`.tap do
      expect($?).to be_success
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
      ENV['LANG'] = lang
      Process.setsid
      Signal.trap("TERM") { exit }

      Warden::Server.setup(
          "server" => {
              "unix_domain_path" => unix_domain_path,
              "container_klass" => container_klass,
              "container_rootfs_path" => container_rootfs_path,
              "container_depot_path" => container_depot_path,
              "container_grace_time" => 5,
              "job_output_limit" => job_output_limit,
              "pidfile" => server_pidfile,
              "syslog_socket" => syslog_socket },
          "network" => {
              "pool_start_address" => @start_address,
              "pool_size" => 64,
              "mtu" => mtu,
              "allow_networks" => allow_networks,
              "allow_host_access" => allow_host_access,
              "dns_servers" => dns_servers },
          "port" => {
              "pool_start_port" => 64000,
              "pool_size" => 1000},
          "logging" => {
              "level" => "debug",
              "file" => File.join(work_path, "warden.log")
          }
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
  it_should_behave_like "writing_pidfile"

  describe "locale when running commands" do
    let(:lang) { "C" }

    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    it "should honor the host's LANG" do
      response = client.run(:handle => handle, :script => "locale | grep LANG=")
      expect(response.exit_status).to eq 0
      expect(response.stdout.strip).to eq "LANG=#{lang}"
      expect(response.stderr).to eq ""
    end

    context "when LANG is not set" do
      let!(:lang) { nil }

      it "defaults to en_US.UTF-8" do
        response = client.run(:handle => handle, :script => "locale | grep LANG=")
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip).to eq 'LANG=en_US.UTF-8'
        expect(response.stderr).to eq ""
      end
    end
  end

  describe 'managing resolv.conf' do
    before do
      @handle = client.create.handle
      @response = client.run(:handle => @handle,
                            :script => 'cat /etc/resolv.conf')
      @host_conf = `cat /etc/resolv.conf`
    end

    context 'when no nameservers are specified in the config' do
      let (:not_dns_servers) { [
        "peter",
        "frank",
        "george"
      ] }

      context 'and the host uses localhost for DNS' do
        before do
          FileUtils.cp('/etc/resolv.conf', '/tmp/resolv.conf')
          `sudo cp spec/assets/config/resolv.conf.localhost /etc/resolv.conf`
          restart_warden
          @client = create_client
          @handle = @client.create.handle
          @network_host_ip = @client.run(:handle => @handle,
            :script => "netstat -rn | awk '/^0\.0\.0\.0/{ print $2 }'")
          @response = client.run(:handle => @handle,
                            :script => 'cat /etc/resolv.conf')
          @expected_conf = "nameserver " + @network_host_ip.stdout.strip
        end

        after do
          `sudo cp /tmp/resolv.conf /etc/resolv.conf`
        end

        it 'points the container at the host for DNS' do
          expect(@response.stdout.strip).to eq(@expected_conf)
        end
      end

      context 'and the host does not use localhost for DNS' do
        it 'copies resolv.conf from the host into the container' do
          expect(@response.stdout).to eq(@host_conf)
        end
      end

      context 'when nameservers are specified in the config' do
        let (:dns_servers) { not_dns_servers }

        it 'copies the nameservers into the container resolv.conf' do
          output = @response.stdout
          dns_servers.each do |ns|
            expect(output.strip.include?("nameserver #{ns}")).to be true
          end

          expect(output.lines.length).to eq(3)
        end
      end
    end
  end

  describe "limit_memory" do
    attr_reader :handle

    def limit_memory(options = {})
      response = client.limit_memory(options.merge(:handle => handle))
      expect(response).to be_ok
      response
    end

    def run(script)
      response = client.run(:handle => handle, :script => script)
      expect(response).to be_ok
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
      expect(response.limit_in_bytes).to eq 9223372036854771712
    end

    describe "setting limits" do
      def integer_from_memory_cgroup(file)
        File.read(File.join("/tmp/warden/cgroup/memory", "instance-#{@handle}", file)).to_i
      end

      let(:hundred_mb) { 100 * 1024 * 1024 }

      before do
        response = limit_memory(:limit_in_bytes => hundred_mb)
        expect(response.limit_in_bytes).to eq hundred_mb
      end

      it "sets `memory.limit_in_bytes`" do
        expect(integer_from_memory_cgroup("memory.limit_in_bytes")).to eq hundred_mb
      end

      it "sets `memory.memsw.limit_in_bytes`" do
        expect(integer_from_memory_cgroup("memory.memsw.limit_in_bytes")).to eq hundred_mb
      end

      describe "increasing limits" do
        before do
          response = limit_memory(:limit_in_bytes => 2 * hundred_mb)
          expect(response.limit_in_bytes).to eq 2 * hundred_mb
        end

        it "sets `memory.limit_in_bytes`" do
          expect(integer_from_memory_cgroup("memory.limit_in_bytes")).to eq 2 * hundred_mb
        end

        it "sets `memory.memsw.limit_in_bytes`" do
          expect(integer_from_memory_cgroup("memory.memsw.limit_in_bytes")).to eq 2 * hundred_mb
        end
      end
    end

    def self.it_should_stop_container_when_an_oom_event_occurs
      it "should stop container when an oom event occurs" do
        trigger_oom

        response = client.info(:handle => handle)
        expect(response.state).to eq "stopped"
        expect(response.events).to include("out of memory")
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
      if not options.has_key? :handle
        options = options.merge(:handle => handle)
      end

      response = client.limit_disk(options)
      expect(response).to be_ok
      response
    end

    def run(script, container_handle = "")
      if container_handle == ""
        container_handle = handle
      end
      response = client.run(:handle => container_handle, :script => script)
      expect(response).to be_ok
      response
    end

    def perform_rsync(src_path, dst_path, exclude_pattern = '')
      # Build arguments
      args  = ["rsync"]
      args += ["-r"]      # Recursive copy
      args += ["-p"]      # Preserve permissions
      args += ["--links"] # Preserve symlinks
      if exclude_pattern != ''
        args += ['--exclude', exclude_pattern]
      end
      args += [src_path + "/", dst_path]

      execute args.join(" ") + "> /dev/null 2> /dev/null"
    end

    before do
      @handle = client.create.handle
    end

    context 'when vcap user exists' do
      attr_reader :vcap_handle

      let(:vcap_rootfs_path) { File.join(work_path, "vcap_rootfs") }
      let(:vcap_home_directory) { File.join(vcap_rootfs_path, "home", "vcap")}
      let(:vcap_home_file) { File.join(vcap_home_directory, "a_file.txt")}
      let(:vcap_tmp_file) { File.join(vcap_rootfs_path, "tmp", "a_file.txt")}

      before do
        if File.exists? vcap_rootfs_path
          FileUtils.rm_rf(vcap_rootfs_path)
        end

        vcap_id = `grep vcap: #{container_rootfs_path}/etc/passwd | cut -d ':' -f 3`.strip

        perform_rsync(container_rootfs_path, vcap_rootfs_path, "mnt/dev/*")
        FileUtils.mkdir_p(vcap_home_directory)
        FileUtils.touch(vcap_home_file)
        FileUtils.touch(vcap_tmp_file)
        FileUtils.chown(vcap_id, vcap_id, vcap_home_directory)
        FileUtils.chown(vcap_id, vcap_id, vcap_home_file)
        FileUtils.chown(vcap_id, vcap_id, vcap_tmp_file)

        create_request = Warden::Protocol::CreateRequest.new
        create_request.rootfs = vcap_rootfs_path

        expect {
          @vcap_handle = client.call(create_request).handle
        }.to_not raise_error
      end

      it 'should apply different disk quota on every container' do
        limit_response = limit_disk(:byte_limit => 4 * 1024 * 1024)
        vcap_limit_response = limit_disk(:handle => vcap_handle, :byte_limit => 4 * 1024 * 1024)

        limit_response = limit_disk()
        expect(limit_response.byte_limit).to eq 4 * 1024 * 1024

        vcap_limit_response = limit_disk(:handle => vcap_handle)
        expect(vcap_limit_response.byte_limit).to eq 4 * 1024 * 1024

        response = run("dd if=/dev/zero of=/tmp/test bs=1M count=3")
        expect(response.exit_status).to eq 0

        response = run("dd if=/dev/zero of=/tmp/test bs=1M count=3", vcap_handle)
        expect(response.exit_status).to eq 0
      end

      it "should still own vcap's files" do
        response = run("stat -c %u /home/vcap/a_file.txt", vcap_handle)
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip!).to eq "10001"

        response = run("stat -c %g /home/vcap/a_file.txt", vcap_handle)
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip!).to eq "10001"

        response = run("stat -c %u /tmp/a_file.txt", vcap_handle)
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip!).to eq "10001"

        response = run("stat -c %g /tmp/a_file.txt", vcap_handle)
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip!).to eq "10001"

        response = run("cat /etc/passwd | grep vcap: | cut -d ':' -f 3", vcap_handle)
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip).to eq "10001"

        response = run("cat /etc/group | grep vcap: | cut -d ':' -f 3", vcap_handle)
        expect(response.exit_status).to eq 0
        expect(response.stdout.strip).to eq "10001"
      end
    end

    it "should allow the disk quota to be changed" do
      response = limit_disk(:block_limit => 12345)
      expect(response.block_limit).to eq 12345
    end

    it "should set the block quota to 0 on creation" do
      # When every test is run in full isolation and even the file
      # system is recreated, this is impossible to test unless we create
      # and destroy containers until we have exhausted the UID pool and
      # re-use an UID for the first time. The test is kept as a reminder.
      response = limit_disk()
      expect(response.block_limit).to eq 0
    end

    context "with a 2M disk limit" do
      before do
        limit_disk(:byte_limit => 2 * 1024 * 1024)
      end

      it "should succeed to write a 1M file" do
        response = run("dd if=/dev/zero of=/tmp/test bs=1M count=1")
        expect(response.exit_status).to eq 0
      end

      it "should fail to write a 4M file" do
        response = run("dd if=/dev/zero of=/tmp/test bs=1M count=4")
        expect(response.exit_status).to eq 1
        expect(response.stderr).to match /quota exceeded/i
      end
    end
  end

  describe "limit output" do
    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    let(:options) { {:handle => handle, :script => script} }

    def run
      response = client.run(options)
      expect(response).to be_ok
      response
    end

    context "when job exceeds output limit" do
      let(:job_output_limit) { 10 }

      let(:script) { "echo BLABLABLABLABLABLA" }

      it "should save event" do
        response = run
        expect(response.info.events).to include("command exceeded maximum output")
      end

      context "when output is discarded" do
        before { options[:discard_output] = true }

        it "does not save an event as the job is not killed" do
          response = run
          expect(response.info.events).to be_nil
        end
      end
    end
  end

  describe "limit_bandwidth" do
    attr_reader :handle

    def limit_bandwidth(options = {})
      response = client.limit_bandwidth(options.merge(:handle => handle))
      expect(response).to be_ok
      response
    end

    before do
      @handle = client.create.handle
    end

    it "should set the bandwidth" do
      response = limit_bandwidth(:rate => 100 * 1000, :burst => 1000)
      ret = client.info(:handle => handle)
      [ret.bandwidth_stat.in_rate, ret.bandwidth_stat.out_rate].each do |v|
        expect(v).to eq 100 * 1000
      end
      [ret.bandwidth_stat.in_burst, ret.bandwidth_stat.out_burst].each do |v|
        expect(v).to eq 1000
      end
    end

    it "should allow bandwidth to be changed" do
      response = limit_bandwidth(:rate => 200 * 1000, :burst => 2000)
      ret = client.info(:handle => handle)
      [ret.bandwidth_stat.in_rate, ret.bandwidth_stat.out_rate].each do |v|
        expect(v).to eq 200 * 1000
      end
      [ret.bandwidth_stat.in_burst, ret.bandwidth_stat.out_burst].each do |v|
        expect(v).to eq 2000
      end
    end
  end

  describe "limit_cpu" do
    attr_reader :handle

    def integer_from_cgroup_cpu_shares
      File.read(File.join("/tmp/warden/cgroup/cpu", "instance-#{@handle}", "cpu.shares")).to_i
    end

    def limit_cpu(options = {})
      response = client.limit_cpu(options.merge(:handle => handle))
      expect(response).to be_ok
      response
    end

    before do
      @handle = client.create.handle
    end

    it "should return the current shares if no share value specified" do
      current_cpu_shares = integer_from_cgroup_cpu_shares
      response = limit_cpu
      expect(response.limit_in_shares).to be current_cpu_shares
    end

    it "should set the cpu shares" do
      response = limit_cpu(:limit_in_shares => 100)
      expect(response.limit_in_shares).to be 100

      expect(integer_from_cgroup_cpu_shares).to be 100
    end

    it "should update the cpu shares" do
      response = limit_cpu(:limit_in_shares => 100)
      expect(response.limit_in_shares).to be 100

      expect(integer_from_cgroup_cpu_shares).to be 100

      response = limit_cpu(:limit_in_shares => 200)
      expect(response.limit_in_shares).to be 200

      expect(integer_from_cgroup_cpu_shares).to be 200
    end

    it "should not set the cpu shares below 2" do
      response = limit_cpu(:limit_in_shares => 1)
      expect(response.limit_in_shares).to be 2

      expect(integer_from_cgroup_cpu_shares).to be 2
    end
  end

  describe "net_out" do
    def net_out(options = {})
      response = client.net_out(options)
      expect(response).to be_ok
      response
    end

    def run(handle, script)
      response = client.run(:handle => handle, :script => script)
      expect(response).to be_ok
      response
    end

    def reachable?(handle, ip)
      response = run(handle, "ping -q -w2 -c1 #{ip}")
      response.exit_status == 0
    end

    def verify_tcp_connectivity(server_container, client_container, port, retry_count = 1)
      # Listen for a connection in server_container
      server_script = "echo ok | nc -l #{port}"
      client.spawn(:handle => server_container[:handle],
                   :script => server_script).job_id

      # Try to connect to the server container
      client_script = "nc -w5 #{server_container[:ip]} #{port}"

      response = nil
      retry_count.times do
        response = run(client_container[:handle], client_script)
        break if response.exit_status == 0
      end

      unless response.exit_status == 0
        # Clean up
        client.run(:handle => server_container[:handle], :script => "pkill -9 nc")
        return false
      end

      true
    end

    def verify_udp_connectivity(server_container, client_container, port, retry_count = 1)
      response = nil
      retry_count.times do |count|
        # Listen for a connection in server_container
        server_script = "nc -u -l #{port}"
        job_id = client.spawn(:handle => server_container[:handle],
                              :script => server_script).job_id

        # Try to connect to the server container
        sleep count
        client_script = "echo ok > /dev/udp/#{server_container[:ip]}/#{port}"
        run(client_container[:handle], client_script)

        client.run(:handle => server_container[:handle], :script => "kill `lsof -t -i :#{port}`")

        response = client.link(:handle => server_container[:handle], :job_id => job_id)
        break if response.stdout.strip == "ok"
      end
      response.stdout.strip == "ok"
    end

    def verify_ping_connectivity(server_container, client_container)
      # Try to ping the server container
      client_script = "ping -c1 -w2 #{server_container[:ip]}"
      response = run(client_container[:handle], client_script)

      response.exit_status == 0
    end

    describe "default networking" do
      attr_reader :handle

      def host_first_ipv4
        Socket.ip_address_list.detect { |intf| intf.ipv4? && !intf.ipv4_loopback? && !intf.ipv4_multicast? }
      end

      before do
        @handle = client.create.handle
      end

      context "when connecting to a remote address" do
        it "rejects outbound udp traffic" do
          client_script = "curl -s --connect-timeout 2 http://www.example.com/ -o /dev/null"
          response = run(handle, client_script)
          expect(response.exit_status).to eq 28 # "Timed out"
        end

        it "rejects outbound tcp traffic" do
          expect(client.net_out(:handle => handle, :port => 53, :protocol => Warden::Protocol::NetOutRequest::Protocol::UDP)).to be_ok

          client_script = "curl -s --connect-timeout 15 http://www.example.com/ -o /dev/null"
          response = run(handle, client_script)
          expect(response.exit_status).to eq 7 # "Failed to connect to host"
        end

        it "rejects outbound icmp traffic" do
          expect(client.net_out(:handle => handle, :port => 53, :protocol => Warden::Protocol::NetOutRequest::Protocol::UDP)).to be_ok

          client_script = "ping -w2 -c1 www.example.com"
          response = run(handle, client_script)
          expect(response.exit_status).to eq 1 # "If ping does not receive any reply packets at all"
        end
      end

      context "when connecting to the host" do
        def verify_tcp_connectivity_to_host(handle, retry_count = 1)
          server_pid = Process.spawn("echo ok | nc -l 8080", pgroup: true)
          client_script = "nc #{host_first_ipv4.ip_address} 8080"

          response = nil
          retry_count.times do
            response = run(handle, client_script)
            break if response.exit_status == 0
          end

          Process.kill("TERM", -Process.getpgid(server_pid))

          response.exit_status == 0
        end

        def verify_udp_connectivity_to_host(handle)
          socket = UDPSocket.new
          socket.bind(host_first_ipv4.ip_address.to_s, 8080)

          client_script = "echo ok > /dev/udp/#{host_first_ipv4.ip_address}/8080"
          response = run(handle, client_script)
          expect(response.exit_status).to eq 0

          begin
            socket.recvfrom_nonblock(3)
            return true
          rescue IO::WaitReadable
            return false
          ensure
            socket.close
          end
        end

        def verify_icmp_connectivity_to_host(handle)
          # Try to ping the host
          client_script = "ping -c1 -w2 #{host_first_ipv4.ip_address}"
          response = client.run(:handle => handle, :script => client_script)
          response.exit_status == 0
        end

        it "rejects outbound tcp traffic" do
          expect(verify_tcp_connectivity_to_host(handle)).to eq false
        end

        it "rejects outbound udp traffic" do
          expect(verify_udp_connectivity_to_host(handle)).to eq false
        end

        it "rejects outbound icmp traffic" do
          expect(verify_icmp_connectivity_to_host(handle)).to eq false
        end

        context "when warden is configured to allow containers to talk to the host" do
          let(:allow_host_access) { true }

          it "allows outbound tcp traffic" do
            expect(verify_tcp_connectivity_to_host(handle, 5)).to eq true
          end

          it "allows outbound udp traffic" do
            expect(verify_udp_connectivity_to_host(handle)).to eq true
          end

          it "allows outbound icmp traffic" do
            expect(verify_icmp_connectivity_to_host(handle)).to eq true
          end
        end
      end

      context "when connecting to another container" do
        before do
          @containers = 2.times.map do
            handle = client.create.handle
            {:handle => handle, :ip => client.info(:handle => handle).container_ip}
          end
        end

        it "does not allow traffic to networks not configured in allowed networks" do
          expect(verify_tcp_connectivity(@containers[0], @containers[1], 2000)).to eq false
          expect(verify_udp_connectivity(@containers[0], @containers[1], 2002)).to eq false
          expect(verify_ping_connectivity(@containers[0], @containers[1])).to eq false
        end
      end
    end

    context "reachability" do
      before do
        @containers = 3.times.map do
          handle = client.create.handle
          {:handle => handle, :ip => client.info(:handle => handle).container_ip}
        end
      end

      it "reaches every container from the host" do
        @containers.each do |e|
          `ping -q -w2 -c1 #{e[:ip]}`
          expect($?).to eq 0
        end
      end

      context "when allow_networks is configured" do
        # Allow traffic to the first two subnets
        host_gw_ip = "8.8.4.4"
        let(:allow_networks) do
          [host_gw_ip]
        end

        it "allows traffic to networks configured in allowed networks" do
          expect(reachable?(@containers[0][:handle], host_gw_ip)).to be true
          expect(reachable?(@containers[1][:handle], host_gw_ip)).to be true
          expect(reachable?(@containers[2][:handle], host_gw_ip)).to be true
        end

        it "disallows traffic to networks that are not configured in allowed networks" do
          expect(reachable?(@containers[0][:handle], "8.8.8.8")).to be false
          expect(reachable?(@containers[1][:handle], "8.8.8.8")).to be false
          expect(reachable?(@containers[2][:handle], "8.8.8.8")).to be false
        end
      end

      describe "net_out control" do
        it "disallows traffic to networks before net_out" do
          expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000)).to eq false
          expect(verify_udp_connectivity(@containers[1], @containers[0], 2000)).to eq false
          expect(verify_ping_connectivity(@containers[2], @containers[1])).to eq false
        end

        it "allows outbound tcp traffic to networks after net_out" do
          net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)
          expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
          client.net_in(:handle => @containers[0][:handle])
          expect(verify_tcp_connectivity(@containers[1], @containers[0], 2001)).to eq false
        end

        it "allows outbound udp traffic to networks after net_out" do
          net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::UDP)
          expect(verify_udp_connectivity(@containers[1], @containers[0], 2000, 3)).to eq true
          expect(verify_udp_connectivity(@containers[1], @containers[0], 2001)).to eq false
        end

        context "icmp" do
          # Assertions testing that containers do NOT have connectivity should only be done
          # between containers that have NEVER had connectivity in any tests. This is because
          # the ESTABLISHED state is cached for 30 seconds and can pollute other tests.
          it "allows outbound icmp traffic after net out" do
            net_out(:handle => @containers[0][:handle],
                    :network => @containers[1][:ip],
                    :protocol => Warden::Protocol::NetOutRequest::Protocol::ICMP,
                    :icmp_type => 8, :icmp_code => 0) # ICMP Echo Request

            expect(verify_ping_connectivity(@containers[1], @containers[0])).to eq true
          end

          it "does not allow outbound when type does not match" do
            net_out(:handle => @containers[1][:handle],
                    :network => @containers[2][:ip],
                    :protocol => Warden::Protocol::NetOutRequest::Protocol::ICMP,
                    :icmp_type => 0, :icmp_code => 0) # ICMP Echo Reply

            expect(verify_ping_connectivity(@containers[2], @containers[1])).to eq false
          end

          it "allows outbound icmp traffic after net out when type and code are -1" do
            net_out(:handle => @containers[0][:handle],
                    :network => @containers[1][:ip],
                    :protocol => Warden::Protocol::NetOutRequest::Protocol::ICMP,
                    :icmp_type => -1, :icmp_code => -1) # Everything

            expect(verify_ping_connectivity(@containers[1], @containers[0])).to eq true
          end

          it "does not allow outbound when code does not match" do
            net_out(:handle => @containers[1][:handle],
                    :network => @containers[2][:ip],
                    :protocol => Warden::Protocol::NetOutRequest::Protocol::ICMP,
                    :icmp_type => 8, :icmp_code => 8) # Bogus code

            expect(verify_ping_connectivity(@containers[2], @containers[1])).to eq false
          end
        end

        context "all protocols" do
          it "allows outbound traffic over all protocols to networks after net_out" do
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :protocol => Warden::Protocol::NetOutRequest::Protocol::ALL)
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2001, 5)).to eq true
            expect(verify_udp_connectivity(@containers[1], @containers[0], 2000, 3)).to eq true
            expect(verify_udp_connectivity(@containers[1], @containers[0], 2001, 3)).to eq true
            expect(verify_ping_connectivity(@containers[1], @containers[0])).to eq true
          end
        end

        xcontext "logs outbound requests" do
          it "logs only tcp traffic" do
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP, :log => true)
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::UDP, :log => true)
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2001, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2001, :protocol => Warden::Protocol::NetOutRequest::Protocol::UDP)
            verify_tcp_connectivity(@containers[1], @containers[0], 2000)
            verify_tcp_connectivity(@containers[1], @containers[0], 2001)
            verify_udp_connectivity(@containers[1], @containers[0], 2000)
            verify_udp_connectivity(@containers[1], @containers[0], 2001)
            verify_ping_connectivity(@containers[1], @containers[0])

            out = `grep -c warden-i-#{@containers[0][:handle]} /var/log/syslog`.chomp
            expect(out).to eq("1")
          end
        end

        context "when port ranges are specified" do
          it "should allow access to all ports in the range" do
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port_range => "2000:2002", :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2001, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2002, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 1999, 5)).to eq false
          end
        end

        context "network using cidr" do
          it "can connect to multiple subnets when the cidr includes them" do
            network = "#{@containers[0][:ip]}/24" # All local warden containers
            net_out(:handle => @containers[0][:handle], :network => network, :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)

            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[2], @containers[0], 2000, 5)).to eq true
          end

          it "cannot connect to a subnet that is not included" do
            network = "#{@containers[1][:ip]}/30" # One server container
            net_out(:handle => @containers[0][:handle], :network => network, :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)

            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[2], @containers[0], 2000)).to eq false
          end
        end

        context "network using range" do
          it "can connect to multiple subnets when the range includes them" do
            first_address = IPAddr.new("#{@containers[0][:ip]}").&(IPAddr.new('255.255.255.0')).to_s
            last_address = IPAddr.new("#{@containers[0][:ip]}").|(IPAddr.new('0.0.0.255')).to_s
            network = "#{first_address}-#{last_address}" # All local warden containers
            net_out(:handle => @containers[0][:handle], :network => network, :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)

            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[2], @containers[0], 2000, 5)).to eq true
          end

          it "cannot connect to a subnet that is not included in the range" do
            first_address = IPAddr.new("#{@containers[1][:ip]}").&(IPAddr.new('255.255.255.252')).to_s
            last_address = IPAddr.new("#{@containers[1][:ip]}").|(IPAddr.new('0.0.0.3')).to_s
            network = "#{first_address}-#{last_address}" # One server container
            net_out(:handle => @containers[0][:handle], :network => network, :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)

            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
            expect(verify_tcp_connectivity(@containers[2], @containers[0], 2000)).to eq false
          end
        end

        context "after restoring from snapshot" do
          it "restores net-out rules to containers with snapshots" do
            net_out(:handle => @containers[0][:handle], :network => @containers[1][:ip], :port => 2000, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)
            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000)).to eq true

            iptable_rule = `/sbin/iptables-save | grep #{@containers[0][:handle]}| grep 2000 | sed -e 's/^-A/-D/'`
            iptable_rule = iptable_rule.chomp
            `iptables #{iptable_rule}`

            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000)).to eq false

            drain_and_restart
            reset_client

            expect(verify_tcp_connectivity(@containers[1], @containers[0], 2000, 5)).to eq true
          end
        end
      end
    end

    describe "check argument handling" do
      let(:handle) { client.create.handle }

      it "should raise error when both fields are absent" do
        expect do
          net_out(:handle => handle)
        end.to raise_error(Warden::Client::ServerError, %r"specify network, port, and/or port_range"i)
      end

      it "should not raise error when network field is present" do
        expect(net_out(:handle => handle, :network => "4.2.2.2")).to be_ok
      end

      it "should not raise error when port field is present" do
        expect(net_out(:handle => handle, :port => 1234)).to be_ok
      end

      it "should not raise error when both network and port fields are present" do
        expect(net_out(:handle => handle, :network => "4.2.2.2", :port => 1234)).to be_ok
      end

      it "should raise an error when the port range specifies min > max" do
        expect do
          net_out(:handle => handle, :port_range => "2002:2000", :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)
        end.to raise_error(Warden::Client::ServerError, %r"port range maximum must be greater than minimum"i)
      end

      it "should raise an error when an unknown protocol is specified" do
        expect do
          net_out(:handle => handle, :protocol => 10)
        end.to raise_error(Warden::Protocol::ProtocolError)
      end
    end
  end

  describe "net_in" do
    attr_reader :handle

    def net_in(options = {})
      response = client.net_in(options.merge(:handle => handle))
      expect(response).to be_ok
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
        `echo | nc -w2 #{external_ip} #{response.host_port}`.chomp == "ok"
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
      expect(response.container_port).to eq 8080
      check_mapping(response)
    end

    it "should allow the port on the host side to be specified" do
      response = net_in(:host_port => 8080)
      expect(response.host_port).to eq 8080
      expect(response.container_port).to eq 8080
      check_mapping(response)
    end

    it "should allow the port on both of the container and host sides to be specified" do
      response = net_in(:host_port => 8080, :container_port => 8081)
      expect(response.host_port).to eq 8080
      expect(response.container_port).to eq 8081
      check_mapping(response)
    end

    it "should not redirect requests to other servers' container_port" do
      expect(client.net_out(:handle => handle, :port => 80)).to be_ok
      expect(client.net_out(:handle => handle, :port => 53, :protocol => Warden::Protocol::NetOutRequest::Protocol::UDP)).to be_ok

      net_in(:host_port => 80, :container_port => 8080)
      script = "curl -s -w '%{http_code}' http://www.example.com/ -o /dev/null"
      job_id = client.spawn(:handle => handle, :script => script).job_id

      response = client.link(:handle => handle, :job_id => job_id)
      expect(response.stdout).to eq("200")
    end
  end

  describe "info" do
    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    it "should include memory stat" do
      response = client.info(:handle => handle)
      expect(response.memory_stat.rss).to be > 0
    end

    it "should include cpu stat" do
      response = client.info(:handle => handle)
      expect(response.cpu_stat.usage).to be > 0
      expect(response.cpu_stat.user).to be >= 0
      expect(response.cpu_stat.system).to be >= 0
    end

    it "should include disk stat" do
      response = client.info(:handle => handle)
      expect(response.disk_stat.inodes_used).to be > 0
      bytes_used = response.disk_stat.bytes_used
      expect(bytes_used).to be > 0

      response = client.run(:handle => handle,
                            :script => "dd if=/dev/urandom of=/tmp/foo bs=1MB count=1")
      expect(response.exit_status).to eq 0

      response = client.info(:handle => handle)
      expect(response.disk_stat.bytes_used).to be_within(32000).of(bytes_used + 1_000_000)
    end

    it "should include bandwidth stat" do
      response = client.info(:handle => handle)
      [response.bandwidth_stat.in_rate, response.bandwidth_stat.out_rate].each do |x|
        expect(x).to be >= 0
      end
      [response.bandwidth_stat.in_burst, response.bandwidth_stat.out_burst].each do |x|
        expect(x).to be >= 0
      end
    end

    it "should include list of ids of jobs that are alive" do
      response = client.spawn(:handle => handle,
                              :script => "sleep 2; id -u")
      job_id_1 = response.job_id

      response = client.spawn(:handle => handle,
                              :script => "id -u")
      job_id_2 = response.job_id

      expect { client.info(:handle => handle).job_ids }.to eventually(eq [job_id_1])
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
      expect(response).to be_ok
      response
    end

    def create
      response = client.call(@create_request)
      expect(response).to be_ok

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
      expect(File.read("/etc/mtab")).to_not match(Regexp.escape(@bind_mount.src_path))
    end

    after :each do
      FileUtils.rm_rf(tmpdir)
    end

    it "should support bind mounting in RO mode" do
      @bind_mount.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO
      create

      # Make sure we CAN READ a file that already exists
      response = run "cat #{@bind_mount.dst_path}/#{test_basename}"
      expect(response.exit_status).to eq 0
      expect(response.stdout).to eq test_contents

      # Make sure we CAN'T WRITE a file
      response = run "touch #{@bind_mount.dst_path}/test"
      expect(response.exit_status).to eq 1
      expect(response.stdout).to be_empty
      expect(response.stderr).to match(/read-only file system/i)
    end

    it "should support bind mounting in RW mode" do
      @bind_mount.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RW
      create

      # Make sure we CAN READ a file that already exists
      response = run "cat #{@bind_mount.dst_path}/#{test_basename}"
      expect(response.exit_status).to eq 0
      expect(response.stdout).to eq test_contents

      # Make sure we CAN WRITE a file
      response = run "touch #{@bind_mount.dst_path}/test"
      expect(response.exit_status).to eq 0
      expect(response.stdout).to be_empty
      expect(response.stderr).to be_empty
    end

    it "should return an error when a bind mount does not exist" do
      @bind_mount.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO
      @bind_mount.src_path = tmpdir + ".doesnt.exist"

      # This will fail from the hook-child-before-pivot hook. It is not
      # possible to check if a bind mount exists before create is executed,
      # because the bind mount may be created _during_ create.
      expect do
        create
      end.to raise_error(Warden::Client::ServerError)
    end
  end

  describe "/dev/shm" do
    attr_reader :handle

    before do
      response = client.create
      expect(response).to be_ok

      @handle = response.handle
    end

    def run(script)
      response = client.run(:handle => handle, :script => script)
      expect(response).to be_ok
      response
    end

    context "when there is a memory limit" do
      let(:megabyte)     { 1024 * 1024 }
      let(:memory_limit) { megabyte * 32 }

      before do
        response = client.limit_memory(:handle => handle, :limit_in_bytes => memory_limit)
        expect(response.limit_in_bytes).to eq memory_limit
      end

      it "can write less than the memory limit" do
        run("dd of=/dev/shm/out.bin if=/dev/urandom bs=#{megabyte} count=30")

        response = client.info(:handle => handle)
        expect(response.state).to eq "active"

        response = run("du -m /dev/shm/out.bin | cut -f1")
        expect(response.stdout.strip.to_i).to be(30)
      end

      it "terminates when writing more data than the memory limit" do
        run("dd of=/dev/shm/out.bin if=/dev/urandom bs=#{megabyte} count=45")

        expect { client.info(:handle => handle).state }.to eventually(eq("stopped"))
        expect { client.info(:handle => handle).events }.to eventually(include("out of memory"))
      end
    end
  end

  describe "network devices" do
    let(:handle) do
      response = client.create
      expect(response).to be_ok

      response.handle
    end

    it "activates a host side network adapter" do
      script = "/sbin/ifconfig w-#{handle}-0 | grep -Eo 'RUNNING'"
      response = execute(script)
      expect(response).to eq("RUNNING\n")
    end

    it "activates a container side network adapter" do
      script = "/sbin/ifconfig w-#{handle}-1 | grep -Eo 'RUNNING'"

      expect {
        @response = client.run(:handle => handle, :script => script)
        @response.stdout
      }.to eventually(eq "RUNNING\n")
      expect(@response.exit_status).to eq 0
    end

    it "activates a host side ifb network adapter" do
      script = "/sbin/ifconfig w-#{handle}-2 | grep -Eo 'RUNNING'"
      response = execute(script)
      expect(response).to eq("RUNNING\n")
    end

    context "when the container is destroyed" do
      before do
        response = client.destroy(:handle => handle)
        expect(response).to be_ok
      end

      it "destroys the host side network adapter" do
        script = "/sbin/ifconfig -a"
        response = execute(script)
        expect(response).to_not include("w-#{handle}-0")
      end

      it "destroys the host side ifb network adapter" do
        script = "/sbin/ifconfig -a"
        response = execute(script)
        expect(response).to_not include("w-#{handle}-2")
      end
    end
  end

  describe "create with network" do
    it "should be able to specify network" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = @start_address

      response = client.call(create_request)
      expect(response).to be_ok

      info_request = Warden::Protocol::InfoRequest.new
      info_request.handle = response.handle

      response = client.call(info_request)
      network = Warden::Network::Address.new(response.container_ip).network(netmask)

      expect(network.to_human).to eq @start_address
    end

    it "should raise error to use network not in the pool" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = '1.1.1.1'

      expect {
        response = client.call(create_request)
      }.to raise_error Warden::Client::ServerError
    end
  end

  describe "create with MTU" do
    let(:mtu) { 1454 }

    it "should set warden side MTU" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = @start_address

      response = client.call(create_request)
      expect(response).to be_ok

      script = "/sbin/ifconfig w-#{response.handle}-1 | grep -Eo 'MTU:[0-9]+'"
      mtu_response = client.run(:handle => response.handle, :script => script)
      expect(mtu_response.stdout).to eq "MTU:1454\n"
    end

    it "should set host side MTU" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = @start_address

      response = client.call(create_request)
      expect(response).to be_ok

      script = "/sbin/ifconfig w-#{response.handle}-0 | grep -Eo 'MTU:[0-9]+'"
      mtu_response = execute("#{script}")
      expect(mtu_response).to eq "MTU:1454\n"
    end

    it "should set the host ifb adapter MTU" do
      create_request = Warden::Protocol::CreateRequest.new
      create_request.network = @start_address

      response = client.call(create_request)
      expect(response).to be_ok

      script = "/sbin/ifconfig w-#{response.handle}-2 | grep -Eo 'MTU:[0-9]+'"
      mtu_response = execute("#{script}")
      expect(mtu_response).to eq "MTU:1454\n"
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
      expect(response).to be_ok
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
      expect(response.exit_status).to eq 0
      expect(response.stdout).to eq "0\n"
      expect(response.stderr).to eq ""
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
      expect(response.exit_status).to eq 0
      expect(response.stdout.chomp).to eq "1234"
      expect(response.stderr.chomp).to eq ""
    end
  end

  describe "recovery" do
    context 'for started containers' do
      before do
        @h1 = client.create.handle
        @h2 = client.create.handle

        stop_warden(:KILL)
      end

      after do
        start_warden

        reset_client

        containers = client.list.handles
        expect(containers).to_not include(@h1)
        expect(containers).to include(@h2)

        # Test that the path for h1 is gone
        h1_path = File.join(container_depot_path, @h1)
        expect(File.directory?(h1_path)).to be false
      end

      it "should destroy containers without snapshot" do
        snapshot_path = File.join(container_depot_path, @h1, "snapshot.json")
        expect(File.exist?(snapshot_path)).to be true
        File.delete(snapshot_path)
      end

      it "should destroy containers that have stopped" do
        wshd_pid_path = File.join(container_depot_path, @h1, "run", "wshd.pid")
        expect(File.exist?(wshd_pid_path)).to be true
        Process.kill("KILL", File.read(wshd_pid_path).to_i)
      end
    end

    context 'for created containers' do
      before do
        @h1 = client.create.handle

        stop_warden(:KILL)
      end

      after do
        start_warden

        reset_client

        containers = client.list.handles
        expect(containers).to be_nil

        # Test that the path for h1 is gone
        h1_path = File.join(container_depot_path, @h1)
        expect(File.directory?(h1_path)).to be false
      end

      it "should destroy containers which have no etc/config" do
        wshd_pid_path = File.join(container_depot_path, @h1, "run", "wshd.pid")
        Process.kill("KILL", File.read(wshd_pid_path).to_i)

        etc_config_path = File.join(container_depot_path, @h1, 'etc','config')
        expect(File.exist?(etc_config_path)).to be true
        File.delete(etc_config_path)
      end
    end
  end

  describe "restoring from snapshot" do
    it "should reset cpu shares for restored containers" do
      handle = client.create.handle
      client.limit_cpu(:handle => handle, :limit_in_shares => 100)

      drain_and_restart

      new_client = create_client

      response = new_client.limit_cpu(:handle => handle)
      expect(response.limit_in_shares).to be 100
    end
  end

  describe "/dev/fuse" do
    attr_reader :handle

    before do
      response = client.create
      expect(response).to be_ok

      @handle = response.handle
    end

    def run(script)
      response = client.run(:handle => handle, :script => script)
      expect(response).to be_ok
      response
    end

    it "is a character special device" do
      response = run("[ -c /dev/fuse ]")
      expect(response.exit_status).to eq 0
    end

    it "can be used by unprivileged users" do
      response = run("id -u")
      expect(response.stdout.strip).to_not eq('0')

      run("mkdir -p /tmp/fuse_ctl")
      expect(response.exit_status).to eq 0

      run("mount -t fusectl none /tmp/fuse_ctl")
      expect(response.exit_status).to eq 0

      run("fusermount -u /fuse_ctl")
      expect(response.exit_status).to eq 0
    end
  end
end
