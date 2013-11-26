require "spec_helper"
require "warden/client/v1"

describe Warden::Client::V1 do
  def to_request(args)
    described_class.request_from_v1(args)
  end

  def to_response(response)
    described_class.response_to_v1(response)
  end

  describe "create" do
    describe "request" do
      describe "bind_mount parameter" do
        it "should use src and dst parameters" do
          request = to_request [
            "create",
            { "bind_mounts" => [["/src", "/dst", "ro"]] },
          ]

          request.bind_mounts.should have(1).bind_mount

          bind_mount = request.bind_mounts.first
          bind_mount.src_path.should == "/src"
          bind_mount.dst_path.should == "/dst"
        end

        ["ro", { "mode" => "ro" }].each do |mode|
          it "should convert ro mode when passed as #{mode.inspect}"  do
            request = to_request [
              "create",
              { "bind_mounts" => [["/src", "/dst", mode]] },
            ]

            request.bind_mounts.should have(1).bind_mount

            bind_mount = request.bind_mounts.first
            bind_mount.src_path.should == "/src"
            bind_mount.dst_path.should == "/dst"
            bind_mount.mode.should == Warden::Protocol::CreateRequest::BindMount::Mode::RO
          end
        end

        ["rw", { "mode" => "rw" }].each do |mode|
          it "should convert rw mode when passed as #{mode.inspect}" do
            request = to_request [
              "create",
              { "bind_mounts" => [["/src", "/dst", "rw"]] },
            ]

            request.bind_mounts.first.mode.should ==
              Warden::Protocol::CreateRequest::BindMount::Mode::RW
          end
        end

        ["rx", { "mode" => "rx" }].each do |mode|
          it "should raise on an invalid mode when passed as #{mode.inspect}" do
            expect do
              to_request [
                "create",
                { "bind_mounts" => [["/src", "/dst", "rx"]] },
              ]
            end.to raise_error
          end
        end
      end

      describe "grace_time parameter" do
        it "should be converted to an integer" do
          request = to_request [
            "create",
            { "grace_time" => 1.1 },
          ]

          request.grace_time.should == 1
        end

        it "should raise on an invalid value" do
          expect do
            to_request [
              "create",
              { "grace_time" => "invalid" },
            ]
          end.to raise_error
        end
      end
    end

    describe "response" do
      it "should return the handle" do
        response = to_response(Warden::Protocol::CreateResponse.new(:handle => "handle"))
        response.should == "handle"
      end
    end
  end

  describe "stop" do
    describe "request" do
      subject { to_request ["stop", "handle"] }

      its(:class)  { should == Warden::Protocol::StopRequest }
      its(:handle) { should == "handle" }
    end

    describe "response" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::StopResponse.new)
        response.should == "ok"
      end
    end
  end

  describe "destroy" do
    describe "request" do
      subject { to_request ["destroy", "handle"] }

      its(:class)  { should == Warden::Protocol::DestroyRequest }
      its(:handle) { should == "handle" }
    end

    describe "response" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::DestroyResponse.new)
        response.should == "ok"
      end
    end
  end

  describe "info" do
    describe "request" do
      subject { to_request ["info", "handle"] }

      its(:class)  { should == Warden::Protocol::InfoRequest }
      its(:handle) { should == "handle" }
    end

    describe "response" do
      let(:response) do
        to_response(
          Warden::Protocol::InfoResponse.new({
            :state => "state",
            :memory_stat => Warden::Protocol::InfoResponse::MemoryStat.new({
              :cache => 1,
              :rss => 2,
            })
          })
        )
      end

      it "should return a hash" do
        response.should be_a(Hash)
      end

      it "should stringify keys" do
        response["state"].should == "state"
      end

      it "should stringify keys of nested hashes" do
        response["memory_stat"]["cache"].should == 1
        response["memory_stat"]["rss"].should == 2
      end
    end
  end

  describe "spawn" do
    describe "request" do
      subject { to_request ["spawn", "handle", "echo foo"] }

      its(:class)  { should == Warden::Protocol::SpawnRequest }
      its(:handle) { should == "handle" }
      its(:script) { should == "echo foo" }
    end

    describe "response" do
      it "should return job_id" do
        response = to_response(Warden::Protocol::SpawnResponse.new(:job_id => 3))
        response.should == 3
      end
    end
  end

  describe "link" do
    describe "request" do
      subject { to_request ["link", "handle", "1"] }

      its(:class)  { should == Warden::Protocol::LinkRequest }
      its(:handle) { should == "handle" }
      its(:job_id) { should == 1 }
    end

    describe "response" do
      it "should return a 3-element tuple" do
        response = to_response(
          Warden::Protocol::LinkResponse.new(
            :exit_status => 255,
            :stdout => "stdout",
            :stderr => "stderr"
          )
        )

        response[0].should == 255
        response[1].should == "stdout"
        response[2].should == "stderr"
      end
    end
  end

  describe "stream" do
    describe "request" do
      subject { to_request ["stream", "handle", "1"] }

      its(:class)  { should == Warden::Protocol::StreamRequest }
      its(:handle) { should == "handle" }
      its(:job_id) { should == 1 }
    end

    describe "response" do
      it "should return a 3-element tuple" do
        response = to_response(
          Warden::Protocol::StreamResponse.new(
            :name => "stdout",
            :data => "data",
            :exit_status => 25
          )
        )

        response[0].should == "stdout"
        response[1].should == "data"
        response[2].should == 25
      end
    end
  end

  describe "run" do
    describe "request" do
      subject { to_request ["run", "handle", "echo foo"] }

      its(:class)  { should == Warden::Protocol::RunRequest }
      its(:handle) { should == "handle" }
      its(:script) { should == "echo foo" }
    end

    describe "response" do
      it "should return a 3-element tuple" do
        response = to_response(
          Warden::Protocol::RunResponse.new(
            :exit_status => 255,
            :stdout => "stdout",
            :stderr => "stderr"
          )
        )

        response[0].should == 255
        response[1].should == "stdout"
        response[2].should == "stderr"
      end
    end
  end

  describe "net" do
    describe "request (in)" do
      subject { to_request ["net", "handle", "in"] }

      its(:class)  { should == Warden::Protocol::NetInRequest }
      its(:handle) { should == "handle" }
    end

    describe "request (out)" do
      subject { to_request ["net", "handle", "out", "network:1234"] }

      its(:class)   { should == Warden::Protocol::NetOutRequest }
      its(:handle)  { should == "handle" }
      its(:network) { should == "network" }
      its(:port)    { should == 1234 }
    end

    describe "response (in)" do
      it "should return a hash with both properties" do
        response = to_response(
          Warden::Protocol::NetInResponse.new(
            :host_port => 1234,
            :container_port => 2345
          )
        )

        response["host_port"].should == 1234
        response["container_port"].should == 2345
      end
    end

    describe "response (out)" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::NetOutResponse.new)
        response.should == "ok"
      end
    end
  end

  describe "copy" do
    describe "request (in)" do
      subject { to_request ["copy", "handle", "in", "/src", "/dst"] }

      its(:class)    { should == Warden::Protocol::CopyInRequest }
      its(:handle)   { should == "handle" }
      its(:src_path) { should == "/src" }
      its(:dst_path) { should == "/dst" }
    end

    describe "request (out)" do
      subject { to_request ["copy", "handle", "out", "/src", "/dst", "owner"] }

      its(:class)    { should == Warden::Protocol::CopyOutRequest }
      its(:handle)   { should == "handle" }
      its(:src_path) { should == "/src" }
      its(:dst_path) { should == "/dst" }
      its(:owner)    { should == "owner" }
    end

    describe "response (in)" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::CopyInResponse.new)
        response.should == "ok"
      end
    end

    describe "response (out)" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::CopyOutResponse.new)
        response.should == "ok"
      end
    end
  end

  describe "limit" do
    describe "request (mem)" do
      describe "without limit" do
        subject { to_request ["limit", "handle", "mem"] }

        its(:class)          { should == Warden::Protocol::LimitMemoryRequest }
        its(:handle)         { should == "handle" }
        its(:limit_in_bytes) { should be_nil }
      end

      describe "with limit" do
        subject { to_request ["limit", "handle", "mem", "1234"] }

        its(:class)          { should == Warden::Protocol::LimitMemoryRequest }
        its(:handle)         { should == "handle" }
        its(:limit_in_bytes) { should == 1234 }
      end
    end

    describe "response (mem)" do
      it "should return #limit_in_bytes" do
        response = to_response(
          Warden::Protocol::LimitMemoryResponse.new({
            :limit_in_bytes => 1234
          })
        )
        response.should == 1234
      end
    end

    describe "request (disk)" do
      describe "without limit" do
        subject { to_request ["limit", "handle", "disk"] }

        its(:class)          { should == Warden::Protocol::LimitDiskRequest }
        its(:handle)         { should == "handle" }
        its(:byte)           { should be_nil }
      end

      describe "with limit" do
        subject { to_request ["limit", "handle", "disk", "1234"] }

        its(:class)          { should == Warden::Protocol::LimitDiskRequest }
        its(:handle)         { should == "handle" }
        its(:byte)           { should == 1234 }
      end
    end

    describe "response (disk)" do
      it "should return #byte" do
        response = to_response(
          Warden::Protocol::LimitDiskResponse.new({
            :byte => 1234
          })
        )
        response.should == 1234
      end
    end
  end

  describe "ping" do
    describe "request" do
      subject { to_request ["ping"] }

      its(:class) { should == Warden::Protocol::PingRequest }
    end

    describe "response" do
      it "should return pong" do
        response = to_response(Warden::Protocol::PingResponse.new)
        response.should == "pong"
      end
    end
  end

  describe "list" do
    describe "request" do
      subject { to_request ["list"] }

      its(:class) { should == Warden::Protocol::ListRequest }
    end

    describe "response" do
      it "should return an array with handles" do
        response = to_response(
          Warden::Protocol::ListResponse.new({
            :handles => ["h1", "h2"]
          })
        )
        response.should == ["h1", "h2"]
      end
    end
  end

  describe "echo" do
    describe "request" do
      subject { to_request ["echo", "hello world"] }

      its(:class)   { should == Warden::Protocol::EchoRequest }
      its(:message) { should == "hello world" }
    end

    describe "response" do
      it "should return #message" do
        response = to_response(
          Warden::Protocol::EchoResponse.new({
            :message => "hello world"
          })
        )
        response.should == "hello world"
      end
    end
  end
end
