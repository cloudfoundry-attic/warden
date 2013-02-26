# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::InfoRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Info" }
  its("class.type_underscored") { should == "info" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::InfoResponse)
  end
end

describe Warden::Protocol::InfoResponse::CpuStat do
  field :usage do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :user do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :system do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end

describe Warden::Protocol::InfoResponse::DiskStat do
  field :bytes_used do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :inodes_used do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end

describe Warden::Protocol::InfoResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Info" }
  its("class.type_underscored") { should == "info" }

  it { should be_ok }
  it { should_not be_error }

  field :state do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :events do
    it_should_be_optional

    it "should allow one or more events" do
      subject.events = ["a", "b"]
      subject.should be_valid
    end
  end

  field :host_ip do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :container_ip do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :container_path do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :cpu_stat do
    it_should_be_optional

    it "should allow instances of CpuStat" do
      subject.cpu_stat = Warden::Protocol::InfoResponse::CpuStat.new
      subject.should be_valid
    end
  end

  field :disk_stat do
    it_should_be_optional

    it "should allow instances of DiskStat" do
      subject.disk_stat = Warden::Protocol::InfoResponse::DiskStat.new
      subject.should be_valid
    end
  end

  field :job_ids do
    it_should_be_optional

    it "should allow one or more job ids" do
      subject.job_ids = [1, 2]
      subject.should be_valid
    end
  end
end
