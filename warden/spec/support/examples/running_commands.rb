# coding: UTF-8

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

  it "should propagate exit status" do
    response = client.run(:handle => handle, :script => "exit 123")
    response.exit_status.should == 123
  end

  it "should terminate when the container is destroyed" do
    client.write(Warden::Protocol::RunRequest.new(:handle => handle, :script => "sleep 5"))

    # Wait for the command to run
    sleep 0.1

    other_client = create_client
    other_client.destroy(:handle => handle)

    # The command should not have exited cleanly
    response = client.read
    response.exit_status.should_not == 0
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
  end
end
