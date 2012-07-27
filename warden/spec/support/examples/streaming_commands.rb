# coding: UTF-8

shared_examples "streaming commands" do
  attr_reader :handle

  before do
    @handle = client.create.handle
  end

  it "works when streaming an unfinished job" do
    response = client.spawn(:handle => handle, :script => "printf A; sleep 0.05; printf B")
    job_id = response.job_id

    sleep 0.0

    client.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

    stdout = ""
    loop do
      response = client.read
      break if response.name.nil?

      response.name.should == "stdout"
      stdout << response.data
    end

    stdout.should == "AB"
    response.exit_status.should == 0
  end

  it "works streaming a finished job" do
    response = client.spawn(:handle => handle, :script => "printf A; sleep 0.05; printf B")
    job_id = response.job_id

    sleep 0.1

    client.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

    stdout = ""
    loop do
      response = client.read
      break if response.name.nil?

      response.name.should == "stdout"
      stdout << response.data
    end

    stdout.should == "AB"
    response.exit_status.should == 0
  end

  context "on different connections" do
    let(:c1) { create_client }
    let(:c2) { create_client }

    it "works when both stream an unfinished job" do
      response = c1.spawn(:handle => handle, :script => "printf A; sleep 0.05; printf B")
      job_id = response.job_id

      sleep 0.0
      c1.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))
      c2.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

      [c1, c2].each do |client|
        stdout = ""
        loop do
          response = client.read
          break if response.name.nil?

          response.name.should == "stdout"
          stdout << response.data
        end

        stdout.should == "AB"
        response.exit_status.should == 0
      end
    end

    it "works when both stream a finished job" do
      response = c1.spawn(:handle => handle, :script => "printf A; sleep 0.05; printf B")
      job_id = response.job_id

      sleep 0.1
      c1.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))
      c2.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

      [c1, c2].each do |client|
        stdout = ""
        loop do
          response = client.read
          break if response.name.nil?

          response.name.should == "stdout"
          stdout << response.data
        end

        stdout.should == "AB"
        response.exit_status.should == 0
      end
    end

    it "works when the one spawning disconnects" do
      response = c1.spawn(:handle => handle, :script => "printf A; sleep 0.05; printf B")
      job_id = response.job_id
      c1.disconnect

      c2.write(Warden::Protocol::StreamRequest.new(:handle => handle, :job_id => job_id))

      [c2].each do |client|
        stdout = ""
        loop do
          response = client.read
          break if response.name.nil?

          response.name.should == "stdout"
          stdout << response.data
        end

        stdout.should == "AB"
        response.exit_status.should == 0
      end
    end
  end
end
