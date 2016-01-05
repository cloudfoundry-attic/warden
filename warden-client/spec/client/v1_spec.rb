require "spec_helper"
require "warden/client/v1"

describe Warden::Client::V1 do
  def to_request(args)
    Warden::Client::V1.request_from_v1(args)
  end

  def to_response(response)
    Warden::Client::V1.response_to_v1(response)
  end

  describe "create" do
    describe "request" do
      describe "bind_mount parameter" do
        it "should use src and dst parameters" do
          request = to_request [
            "create",
            { "bind_mounts" => [["/src", "/dst", "ro"]] },
          ]

          expect(request.bind_mounts.size).to eq(1)

          bind_mount = request.bind_mounts.first
          expect(bind_mount.src_path).to eq("/src")
          expect(bind_mount.dst_path).to eq("/dst")
        end

        ["ro", { "mode" => "ro" }].each do |mode|
          it "should convert ro mode when passed as #{mode.inspect}"  do
            request = to_request [
              "create",
              { "bind_mounts" => [["/src", "/dst", mode]] },
            ]

            expect(request.bind_mounts.size).to eq(1)

            bind_mount = request.bind_mounts.first
            expect(bind_mount.src_path).to eq("/src")
            expect(bind_mount.dst_path).to eq("/dst")
            expect(bind_mount.mode).to eq(Warden::Protocol::CreateRequest::BindMount::Mode::RO)
          end
        end

        ["rw", { "mode" => "rw" }].each do |mode|
          it "should convert rw mode when passed as #{mode.inspect}" do
            request = to_request [
              "create",
              { "bind_mounts" => [["/src", "/dst", "rw"]] },
            ]

            expect(request.bind_mounts.first.mode).to eq( Warden::Protocol::CreateRequest::BindMount::Mode::RW)
          end
        end

        ["rx", { "mode" => "rx" }].each do |mode|
          it "should raise on an invalid mode when passed as #{mode.inspect}" do
            expect do
              to_request [
                "create",
                { "bind_mounts" => [["/src", "/dst", "rx"]] },
              ]
            end.to raise_error NameError
          end
        end
      end

      describe "grace_time parameter" do
        it "should be converted to an integer" do
          request = to_request [
            "create",
            { "grace_time" => 1.1 },
          ]

          expect(request.grace_time).to eq(1)
        end

        it "should raise on an invalid value" do
          expect do
            to_request [
              "create",
              { "grace_time" => "invalid" },
            ]
          end.to raise_error ArgumentError
        end
      end
    end

    describe "response" do
      it "should return the handle" do
        response = to_response(Warden::Protocol::CreateResponse.new(:handle => "handle"))
        expect(response).to eq("handle")
      end
    end
  end

  describe "stop" do
    describe "request" do
      subject { to_request ["stop", "handle"] }

      it 'is a StopRequest' do
        expect(subject).to be_a Warden::Protocol::StopRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end
    end

    describe "response" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::StopResponse.new)
        expect(response).to eq("ok")
      end
    end
  end

  describe "destroy" do
    describe "request" do
      subject { to_request ["destroy", "handle"] }

      it 'is a DestroyRequest' do
        expect(subject).to be_a Warden::Protocol::DestroyRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end
    end

    describe "response" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::DestroyResponse.new)
        expect(response).to eq("ok")
      end
    end
  end

  describe "info" do
    describe "request" do
      subject { to_request ["info", "handle"] }

      it 'is a InfoRequest' do
        expect(subject).to be_a Warden::Protocol::InfoRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end
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
        expect(response).to be_a(Hash)
      end

      it "should stringify keys" do
        expect(response["state"]).to eq("state")
      end

      it "should stringify keys of nested hashes" do
        expect(response["memory_stat"]["cache"]).to eq(1)
        expect(response["memory_stat"]["rss"]).to eq(2)
      end
    end
  end

  describe "spawn" do
    describe "request" do
      subject { to_request ["spawn", "handle", "echo foo"] }

      it 'is a SpawnRequest' do
        expect(subject).to be_a Warden::Protocol::SpawnRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a script' do
        expect(subject.script).to eq('echo foo')
      end
    end

    describe "response" do
      it "should return job_id" do
        response = to_response(Warden::Protocol::SpawnResponse.new(:job_id => 3))
        expect(response).to eq(3)
      end
    end
  end

  describe "link" do
    describe "request" do
      subject { to_request ["link", "handle", "1"] }

      it 'is a LinkRequest' do
        expect(subject).to be_a Warden::Protocol::LinkRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a job id' do
        expect(subject.job_id).to eq(1)
      end
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

        expect(response[0]).to eq(255)
        expect(response[1]).to eq("stdout")
        expect(response[2]).to eq("stderr")
      end
    end
  end

  describe "stream" do
    describe "request" do
      subject { to_request ["stream", "handle", "1"] }

      it 'is a StreamRequest' do
        expect(subject).to be_a Warden::Protocol::StreamRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a job id' do
        expect(subject.job_id).to eq(1)
      end
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

        expect(response[0]).to eq("stdout")
        expect(response[1]).to eq("data")
        expect(response[2]).to eq(25)
      end
    end
  end

  describe "run" do
    describe "request" do
      subject { to_request ["run", "handle", "echo foo"] }

      it 'is a RunRequest' do
        expect(subject).to be_a Warden::Protocol::RunRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a script' do
        expect(subject.script).to eq('echo foo')
      end
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

        expect(response[0]).to eq(255)
        expect(response[1]).to eq("stdout")
        expect(response[2]).to eq("stderr")
      end
    end
  end

  describe "net" do
    describe "request (in)" do
      subject { to_request ["net", "handle", "in"] }

      it 'is a NetInRequest' do
        expect(subject).to be_a Warden::Protocol::NetInRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end
    end

    describe "request (out)" do
      subject { to_request ["net", "handle", "out", "network:1234"] }

      it 'is a NetOutRequest' do
        expect(subject).to be_a Warden::Protocol::NetOutRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a network' do
        expect(subject.network).to eq('network')
      end

      it 'has a port' do
        expect(subject.port).to eq(1234)
      end
    end

    describe "response (in)" do
      it "should return a hash with both properties" do
        response = to_response(
          Warden::Protocol::NetInResponse.new(
            :host_port => 1234,
            :container_port => 2345
          )
        )

        expect(response["host_port"]).to eq(1234)
        expect(response["container_port"]).to eq(2345)
      end
    end

    describe "response (out)" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::NetOutResponse.new)
        expect(response).to eq("ok")
      end
    end
  end

  describe "copy" do
    describe "request (in)" do
      subject { to_request ["copy", "handle", "in", "/src", "/dst"] }

      it 'is a CopyInRequest' do
        expect(subject).to be_a Warden::Protocol::CopyInRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a source path' do
        expect(subject.src_path).to eq('/src')
      end

      it 'has a destination path' do
        expect(subject.dst_path).to eq('/dst')
      end
    end

    describe "request (out)" do
      subject { to_request ["copy", "handle", "out", "/src", "/dst", "owner"] }

      it 'is a CopyOutRequest' do
        expect(subject).to be_a Warden::Protocol::CopyOutRequest
      end

      it 'has a handle' do
        expect(subject.handle).to eq('handle')
      end

      it 'has a source path' do
        expect(subject.src_path).to eq('/src')
      end

      it 'has a destination path' do
        expect(subject.dst_path).to eq('/dst')
      end

      it 'has an owner' do
        expect(subject.owner).to eq('owner')
      end
    end

    describe "response (in)" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::CopyInResponse.new)
        expect(response).to eq("ok")
      end
    end

    describe "response (out)" do
      it "should always be ok" do
        response = to_response(Warden::Protocol::CopyOutResponse.new)
        expect(response).to eq("ok")
      end
    end
  end

  describe "limit" do
    describe "request (mem)" do
      describe "without limit" do
        subject { to_request ["limit", "handle", "mem"] }

        it 'is a LimitMemoryRequest' do
          expect(subject).to be_a Warden::Protocol::LimitMemoryRequest
        end

        it 'has a handle' do
          expect(subject.handle).to eq('handle')
        end

        it 'has no limit' do
          expect(subject.limit_in_bytes).to be_nil
        end
      end

      describe "with limit" do
        subject { to_request ["limit", "handle", "mem", "1234"] }

        it 'is a LimitMemoryRequest' do
          expect(subject).to be_a Warden::Protocol::LimitMemoryRequest
        end

        it 'has a handle' do
          expect(subject.handle).to eq('handle')
        end

        it 'has a limit' do
          expect(subject.limit_in_bytes).to eq(1234)
        end
      end
    end

    describe "response (mem)" do
      it "should return #limit_in_bytes" do
        response = to_response(
          Warden::Protocol::LimitMemoryResponse.new({
            :limit_in_bytes => 1234
          })
        )
        expect(response).to eq(1234)
      end
    end

    describe "request (disk)" do
      describe "without limit" do
        subject { to_request ["limit", "handle", "disk"] }

        it 'is a LimitDiskRequest' do
          expect(subject).to be_a Warden::Protocol::LimitDiskRequest
        end

        it 'has a handle' do
          expect(subject.handle).to eq('handle')
        end

        it 'has no limit' do
          expect(subject.byte).to be_nil
        end
      end

      describe "with limit" do
        subject { to_request ["limit", "handle", "disk", "1234"] }

        it 'is a LimitDiskRequest' do
          expect(subject).to be_a Warden::Protocol::LimitDiskRequest
        end

        it 'has a handle' do
          expect(subject.handle).to eq('handle')
        end

        it 'has a limit' do
          expect(subject.byte).to eq(1234)
        end
      end
    end

    describe "response (disk)" do
      it "should return #byte" do
        response = to_response(
          Warden::Protocol::LimitDiskResponse.new({
            :byte => 1234
          })
        )
        expect(response).to eq(1234)
      end
    end
  end

  describe "ping" do
    describe "request" do
      subject { to_request ["ping"] }

      it 'is a PingRequest' do
        expect(subject).to be_a Warden::Protocol::PingRequest
      end
    end

    describe "response" do
      it "should return pong" do
        response = to_response(Warden::Protocol::PingResponse.new)
        expect(response).to eq("pong")
      end
    end
  end

  describe "list" do
    describe "request" do
      subject { to_request ["list"] }

      it 'is a ListRequest' do
        expect(subject).to be_a Warden::Protocol::ListRequest
      end
    end

    describe "response" do
      it "should return an array with handles" do
        response = to_response(
          Warden::Protocol::ListResponse.new({
            :handles => ["h1", "h2"]
          })
        )
        expect(response).to eq(["h1", "h2"])
      end
    end
  end

  describe "echo" do
    describe "request" do
      subject { to_request ["echo", "hello world"] }

      it 'is a EchoRequest' do
        expect(subject).to be_a Warden::Protocol::EchoRequest
      end

      it 'has a message' do
        expect(subject.message).to eq('hello world')
      end
    end

    describe "response" do
      it "should return #message" do
        response = to_response(
          Warden::Protocol::EchoResponse.new({
            :message => "hello world"
          })
        )
        expect(response).to eq("hello world")
      end
    end
  end
end
