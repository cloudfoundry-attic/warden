# coding: UTF-8

require "spec_helper"
require "net/http"
require "uri"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"

require "warden/container/linux"

describe "health check" do
  let(:work_path) { File.join(Dir.tmpdir, "warden", "spec") }
  let(:unix_domain_path) { File.join(work_path, "warden.sock") }
  let(:container_klass) { "Warden::Container::Linux" }
  let(:container_rootfs_path) { File.join(work_path, "..", "rootfs") }
  let(:container_depot_path) { File.join(work_path, "containers") }

  before do
     FileUtils.mkdir_p(work_path)

    unless File.directory?(container_rootfs_path)
      raise "%s does not exist" % container_rootfs_path
    end

    FileUtils.mkdir_p(container_depot_path)
  end

  before do
    start_warden
  end

  def start_warden
    FileUtils.rm_f(unix_domain_path)

    # Grab new network for every test to avoid resource contention
    @start_address = next_class_c.to_human

    @pid = fork do
      Process.setsid
      Signal.trap("TERM") { exit }

      config = {
        "server" => {
          "unix_domain_path" => unix_domain_path,
          "container_rootfs_path" => container_rootfs_path,
          "container_depot_path" => container_depot_path,
          "container_grace_time" => 5
        },
        "health_server" => {
          "port" => 2345
        },
        "logging" => {
          "level" => "debug",
          "file" => File.join(work_path, "warden.log")
        }
      }
      Warden::Server.setup(config)
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

  after do
    `kill -9 -#{@pid}`
    Process.waitpid(@pid)
  end

  it "should respond with HTTP 200" do
    uri = URI.parse("http://127.0.0.1:2345/")
    response = Net::HTTP.get_response(uri)
    response.code.should == "200"
    response.body.should be_empty
  end
end
