# coding: UTF-8

# this file has the tests for nested warden feature.
# These tests don't fit into linux_spec.rb because in linux_spec.rb all before/after hooks are :each,
# but we need :all since setting up nested warden container is very expensive.
# TODO: This file has some duplication with linux_spec.rb. Refactoring is needed later.

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

    execute("rm -rf #{container_depot_path}")

  end

  def execute(command)
    `#{command}`.tap do
      $?.should be_success
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

      # whiteout rootfs/dev beforehand to avoid 'overlayfs: operation not permitted' error
      `rm -rf /tmp/warden/rootfs/dev/*`

      @bind_mount_warden = Warden::Protocol::CreateRequest::BindMount.new
      @bind_mount_warden.src_path = File.join(warden_repo, 'warden')
      @bind_mount_warden.dst_path = "/warden"
      @bind_mount_warden.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO

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
      run_as_root 'source /etc/profile.d/rvm.sh; cd /warden && BUNDLE_APP_CONFIG=/tmp/.bundle bundle install --quiet'
      run_as_root 'rm /tmp/warden.sock || true'
      run_as_root 'source /etc/profile.d/rvm.sh; cd /warden && bundle exec rake warden:start[spec/assets/config/child-linux.yml] &'

      sleep 5 #wait warden server to start up

      run_as_root 'ls /tmp/warden.sock'
    end

    after :all do

      #destroy nested containers if there is any
      run_as_root '/warden/root/linux/clear.sh /tmp/warden/containers > /dev/null'

      #stop child warden server
      run_as_root "ps -ef|grep [r]ake |awk '{print $2}'|xargs kill"
    end

    it 'should run nested containers' do

      run_as_root 'source /etc/profile.d/rvm.sh; /warden/bin/warden -- create'

    end

    it 'should setup nested cgroup' do

      run_as_root 'source /etc/profile.d/rvm.sh; /warden/bin/warden -- create'
      Dir.glob("/tmp/warden/cgroup/cpu/instance-#{handle}/instance-*").should_not be_empty

    end

    it 'should allow inbound traffic to nested containers' do

      #ping the nested container from host
      execute "route add -net 10.254.0.0/22 gw 10.244.0.2"
      run_as_root 'source /etc/profile.d/rvm.sh; /warden/bin/warden -- create --network 10.254.0.126'
      execute 'ping -c3 10.254.0.126'
      execute "route del -net 10.254.0.0/22 gw 10.244.0.2"
    end

    it 'should allow outbound traffic from nested containers' do

      #create a nested container and have it download something
      run_as_root 'source /etc/profile.d/rvm.sh; handle=`/warden/bin/warden -- create | cut -d' ' -f3`;
        /warden/bin/warden -- run --handle $handle --script "curl http://rvm.io" '

    end
  end
end
