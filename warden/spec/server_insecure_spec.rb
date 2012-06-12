require "spec_helper"

shared_context :server_insecure do

  include_context :warden_server
  include_context :warden_client

  let(:container_klass) {
    Warden::Container::Insecure
  }

  let (:client) {
    create_client
  }
end

describe "server implementing insecure containers" do
  it_behaves_like "a warden server", Warden::Container::Insecure

  describe "network forwarding", :netfilter => true do

    include_context :server_insecure

    before(:each) do
      @handle = client.create
    end

    after(:each) do
      # Verify that the port mapping in @ports works
      job = client.spawn(@handle, "echo ok | nc -l #{@ports["container_port"]}")

      # Give nc some time to start
      sleep 0.050

      # Connect via external IP
      external_ip = `ip route get 1.1.1.1`.split(/\n/).first.split(/\s+/).last
      `nc #{external_ip} #{@ports["host_port"]}`.chomp.should == "ok"

      # Clean up
      client.link(@handle, job)
    end

    it "should work" do
      @ports = client.net(@handle, :in)
    end

    it "should ignore the container side port if specified" do
      @ports = client.net(@handle, :in, 1234)
      @ports["container_port"].should_not == 1234
    end
  end
end
