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
  let(:mtu) { 1500 }
  let(:nested_linux_config) {

     {   "server" => {
            "unix_domain_path" => unix_domain_path,
            "container_klass" => container_klass,
            "container_rootfs_path" => container_rootfs_path,
            "container_depot_path" => container_depot_path,
            "container_grace_time" => nil,
            "job_output_limit" => 100 * 1024,
            "allow_nested_warden" => true  },
        "network" => {
            "pool_start_address" => "10.244.0.0",
            "pool_size" => 64,
            "mtu" => mtu,
            "allow_networks" => allow_networks,
            "deny_networks" => deny_networks },
        "port" => {
            "pool_start_port" => 64000,
            "pool_size" => 1000 },
        "logging" => {
            "level" => "debug",
            "file" => File.join(work_path, "warden.log") }
    }
  }

  before :all do
    FileUtils.mkdir_p(work_path)

    unless File.directory?(container_rootfs_path)
      raise "%s does not exist" % container_rootfs_path
    end

    FileUtils.mkdir_p(container_depot_path)

    start_warden
  end

  after :all do

    stop_warden

    # Destroy all artifacts
    Dir[File.join(Warden::Util.path("root"), "*", "clear.sh")].each do |clear|
      execute("#{clear} #{container_depot_path} > /dev/null")
    end

    #execute("rmdir #{container_depot_path}")

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

  def start_warden(config=nil)
    FileUtils.rm_f(unix_domain_path)

    # Grab new network for every test to avoid resource contention
    @start_address = next_class_c.to_human
    config ||= nested_linux_config
    @pid = fork do
      Process.setsid
      Signal.trap("TERM") { exit }

      Warden::Server.setup config
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


  describe "nested" do

    attr_reader :handle

    def run_as_root(script)
      response = client.run(:handle => handle, :script => script, :privileged => true)
      puts response.stdout, response.stderr unless response.exit_status == 0
      response.exit_status.should == 0

    end

    def create
      response = client.call(@create_request)
      response.should be_ok

      @handle = response.handle
    end

    before :all do

      warden_repo = File.expand_path('../../../..' ,__FILE__)

      @bind_mount_warden = Warden::Protocol::CreateRequest::BindMount.new
      @bind_mount_warden.src_path = File.join(warden_repo, 'warden')
      @bind_mount_warden.dst_path = "/warden"
      @bind_mount_warden.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO

      # whiteout rootfs/dev beforehand to avoid 'overlayfs: operation not permitted'
      `rm -rf /tmp/warden/rootfs/dev/*`
      @bind_mount_rootfs = Warden::Protocol::CreateRequest::BindMount.new
      @bind_mount_rootfs.src_path = "/tmp/warden/rootfs"
      @bind_mount_rootfs.dst_path = "/tmp/warden/rootfs"
      @bind_mount_rootfs.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO

      @create_request = Warden::Protocol::CreateRequest.new
      @create_request.bind_mounts = [@bind_mount_warden, @bind_mount_rootfs]

      create

      run_as_root 'apt-get -qq -y install iptables'
      run_as_root 'sed -i s/lucid/precise/ /etc/lsb-release'
      run_as_root 'curl -L https://get.rvm.io | bash -s stable'
      ruby_version = File.read(File.join(warden_repo, '.ruby-version')).chomp
      run_as_root "source /etc/profile.d/rvm.sh; rvm install #{ruby_version}"
      run_as_root 'source /etc/profile.d/rvm.sh; gem install bundler --no-rdoc --no-ri'
      run_as_root 'source /etc/profile.d/rvm.sh; cd /warden && bundle install --quiet'
      run_as_root 'rm /tmp/warden.sock || true'
      run_as_root 'source /etc/profile.d/rvm.sh; cd /warden && bundle exec rake warden:start[spec/assets/config/child-linux.yml] &'
      puts "GGGG warden server should be running, please check"
      sleep 5 #wait ward server start up

      run_as_root 'ls /tmp/warden.sock'
    end

    after :all do

      run_as_root "ps -ef|grep [r]ake |awk '{print $2}'|xargs kill"
    end

    it 'should run nested containers' do

      run_as_root 'source /etc/profile.d/rvm.sh; /warden/bin/warden -- create'
      sleep 10 # wait containers to die

    end

    it 'should setup nested cgroup' do

      run_as_root 'source /etc/profile.d/rvm.sh; /warden/bin/warden -- create'
      puts `/tmp/warden/cgroup/cpu/instance-#{handle}/instance-*`
      Dir.glob("/tmp/warden/cgroup/cpu/instance-#{handle}/instance-*").should_not be_empty
      sleep 10 # wait containers to die
      sleep 60*10

      puts

    end

    xit 'should allow inbond traffic to nested container' do
    end

  end
end