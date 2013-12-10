# coding: UTF-8

module Warden::Protocol
  shared_examples "running commands" do
    attr_reader :handle

    before do
      @handle = client.create.handle
    end

    it "should redirect stdout output" do
      response = client.run(:handle => handle, :script => "echo hi")
      response.exit_status.should == 0
      response.stdout.should == "hi\n"
      response.stderr.should == ""
    end

    it "should redirect stderr output" do
      response = client.run(:handle => handle, :script => "echo hi 1>&2")
      response.exit_status.should == 0
      response.stdout.should == ""
      response.stderr.should == "hi\n"
    end

    context "when log_tag is given" do
      let(:socket_dir) { Dir.mktmpdir }
      let(:syslog_socket) { File.join(socket_dir, "log.sock") }

      class SocketServer
        def initialize(socket_path)
          @socket_server = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM, 0)
          @socket_server.bind(Socket.pack_sockaddr_un(socket_path))
        end

        def received_messages(num)
          messages = []
          num.times do
            messages << @socket_server.recvfrom(10*1024*1024)
          end
          messages.flatten
        end
      end

      before do
        # we need to start socket server before we start warden
        stop_warden
        @client = nil

        @socket_server = SocketServer.new(syslog_socket)
        start_warden
      end

      after { FileUtils.rm_rf(socket_dir) }

      it "logs syslog to the configured socket file with the given tag via run" do
        em(timeout: 5) do
          request = Warden::Protocol::RunRequest.new
          request.handle = handle
          request.script = "echo hi out; echo hi err 1>&2"
          request.log_tag = "some_log_tag"
          client.call(request)
          EM.stop
        end

        messages_received = @socket_server.received_messages(2).to_s

        expect(messages_received).to match /<14>.*warden.some_log_tag: hi out/
        expect(messages_received).to match /<11>.*warden.some_log_tag: hi err/
      end

      it "logs syslog to the configured socket file with the given tag via spawn" do
        em(timeout: 5) do
          request = Warden::Protocol::SpawnRequest.new
          request.handle = handle
          request.script = "echo hi out; echo hi err 1>&2"
          request.log_tag = "some_log_tag"
          client.call(request)
          EM.stop
        end

        messages_received = @socket_server.received_messages(2).to_s

        expect(messages_received).to match /<14>.*warden.some_log_tag: hi out/
        expect(messages_received).to match /<11>.*warden.some_log_tag: hi err/
      end
    end

    it "should propagate exit status" do
      response = client.run(:handle => handle, :script => "exit 123")
      response.exit_status.should == 123
    end

    context "when the container is destroyed" do
      before do
        client.write(RunRequest.new(:handle => handle, :script => "sleep 5"))

        # Wait for the command to run
        sleep 0.1
      end

      it "terminates cleanly" do
        other_client = create_client
        other_client.destroy(:handle => handle)

        # The command should not have exited cleanly
        response = client.read
        response.exit_status.should_not == 0
      end

      it "includes container info" do
        other_client = create_client
        other_client.destroy(:handle => handle)

        response = client.read
        response.info.should be_kind_of(InfoResponse)
      end
    end

    it "should return an error when the handle is unknown" do
      expect do
        client.run(:handle => handle.next, :script => "echo")
      end.to raise_error(/unknown handle/i)
    end

    describe "via spawn/link" do
      it "should link an unfinished job" do
        response = client.spawn(:handle => handle, :script => "sleep 0.1")
        job_id = response.job_id

        sleep 0.0
        response = client.link(:handle => handle, :job_id => job_id)
        response.exit_status.should == 0
      end

      it "should link a finished job" do
        response = client.spawn(:handle => handle, :script => "sleep 0.0")
        job_id = response.job_id

        sleep 0.1
        response = client.link(:handle => handle, :job_id => job_id)
        response.exit_status.should == 0
      end

      it "should return an error after a job has already been linked" do
        job_id = client.spawn(:handle => handle, :script => "sleep 0.0").job_id
        client.link(:handle => handle, :job_id => job_id).should_not be_nil

        expect do
          client.link(:handle => handle, :job_id => job_id)
        end.to raise_error(Warden::Client::ServerError, "no such job")
      end

      describe "on different connections" do
        let(:c1) { create_client }
        let(:c2) { create_client }

        attr_reader :job_id

        before do
          @job_id = c1.spawn(:handle => handle, :script => "sleep 0.1").job_id
        end

        after do
          expect do
            c = create_client
            c.link(:handle => handle, :job_id => job_id)
          end.to raise_error(Warden::Client::ServerError, "no such job")
        end

        it "should work when both link an unfinished job" do
          c1.write(Warden::Protocol::LinkRequest.new(:handle => handle, :job_id => job_id))
          c2.write(Warden::Protocol::LinkRequest.new(:handle => handle, :job_id => job_id))

          r1 = c1.read
          r2 = c2.read
          r1.should == r2
        end

        it "should work when the connection that spawned the job disconnects" do
          c1.disconnect

          response = c2.link(:handle => handle, :job_id => job_id)
          response.exit_status.should == 0
        end
      end

      describe "buffer limits" do
        let(:discard_output) { false }

        context "when the output is not discarded" do
          [[:stdout, 1], [:stderr, 2]].each do |(io, fd)|
            it "should kill a job exceeding #{io} buffer limit" do
              script = "( head -c #{1024 * 200} /dev/urandom; sleep 1 ) 1>&#{fd}"
              response = client.run(:handle => handle, :script => script, :discard_output => discard_output)

              response.exit_status.should == 255
              response.send(io).size.should > 1024 * 100
              response.send(io).size.should <= 1024 * 100 + 1024 * 64

              # Test that iomux-spawn was killed
              `ps ax | grep iomux-spawn | grep #{handle} | grep -v grep`.should == ""
            end
          end
        end

        context "when output is discarded" do
          let(:discard_output) { true }

          [[:stdout, 1], [:stderr, 2]].each do |(io, fd)|
            it "should clear the buffer after reading" do
              script = "( head -c #{1024 * 200} /dev/urandom; sleep 1 ) 1>&#{fd}"
              response = client.run(:handle => handle, :script => script, :discard_output => discard_output)

              response.exit_status.should == 0
              response.send(io).size.should == 0
            end
          end
        end
      end
    end

    describe "via spawn/stream" do
      def stream(client, job_id)
        client.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

        rv = []
        while response = client.read
          rv << response
          break if !response.exit_status.nil?
        end

        rv
      end

      it "should stream an unfinished job" do
        job_id = client.spawn(:handle => handle, :script => "printf A; sleep 0.1; printf B;").job_id

        r = stream(client, job_id)
        r.select { |e| e.name == "stdout" }.collect(&:data).join.should == "AB"
        r.select { |e| e.name == "stderr" }.collect(&:data).join.should == ""
        r.last.exit_status.should == 0
      end

      it "includes container info" do
        job_id = client.spawn(:handle => handle, :script => "printf A; sleep 0.1; printf B;").job_id

        r = stream(client, job_id)
        r.last.info.should be_kind_of(InfoResponse)
      end

      it "should stream a finished job" do
        job_id = client.spawn(:handle => handle, :script => "printf A; sleep 0.0; printf B;").job_id

        sleep 0.1

        r = stream(client, job_id)
        r.select { |e| e.name == "stdout" }.collect(&:data).join.should == "AB"
        r.select { |e| e.name == "stderr" }.collect(&:data).join.should == ""
        r.last.exit_status.should == 0
      end

      it "should return an error after a job has already been streamed" do
        job_id = client.spawn(:handle => handle, :script => "sleep 0.0").job_id

        r = stream(client, job_id)
        r.should_not be_empty

        expect do
          stream(client, job_id)
        end.to raise_error(Warden::Client::ServerError, "no such job")
      end

      it "should stream a finished job after another connection streamed and was terminated before completion" do
        job_id = client.spawn(:handle => handle, :script => "for i in $(seq 2); do echo $i; sleep 0.1; done").job_id

        client.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

        client.disconnect

        sleep 0.3

        client.reconnect

        # Attempt to stream the job again; the server should have left it in tact
        r = stream(client, job_id)
        r.select { |e| e.name == "stdout" }.collect(&:data).join.should == "1\n2\n"
        r.select { |e| e.name == "stderr" }.collect(&:data).join.should == ""
        r.last.exit_status.should == 0
      end

      describe "on different connections" do
        let(:c1) { create_client }
        let(:c2) { create_client }

        attr_reader :job_id

        before do
          @job_id = c1.spawn(:handle => handle, :script => "sleep 0.1").job_id
        end

        after do
          expect do
            c = create_client
            c.link(:handle => handle, :job_id => job_id)
          end.to raise_error(Warden::Client::ServerError, "no such job")
        end

        it "should work when both stream an unfinished job" do
          r = [c1, c2].map do |c|
            Thread.new do
              Thread.current[:result] = stream(c, job_id)
            end
          end.map do |t|
            t.join
            # we don't care to compare container info
            t[:result].each { |r| r.info = nil }
          end

          r[0].should == r[1]
        end

        it "should work when the connection that spawned the job disconnects" do
          c1.disconnect

          r = stream(c2, job_id)
          r.should_not be_empty
        end
      end

      describe "buffer limits" do
        [[:stdout, 1], [:stderr, 2]].each do |(io, fd)|
          it "should kill a job exceeding #{io} buffer limit" do
            script = "( head -c #{1024 * 200} /dev/urandom; sleep 1 ) 1>&#{fd}"
            job_id = client.spawn(:handle => handle, :script => script).job_id

            responses = stream(client, job_id)
            responses.last.exit_status.should == 255
            responses.map(&:data).join.size.should > 1024 * 100
            responses.map(&:data).join.size.should <= 1024 * 100 + 1024 * 64

            # Test that iomux-spawn was killed
            `ps ax | grep iomux-spawn | grep #{handle} | grep -v grep`.should == ""
          end
        end
      end
    end

    it "streaming a finished job should fail after it's been linked"
    it "linking a finished job should fail after it's been streamed"
  end
end
