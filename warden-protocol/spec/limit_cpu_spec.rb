# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::LimitCpuRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "LimitCpu" }
  its("class.type_underscored") { should == "limit_cpu" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :limit_in_shares do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::LimitCpuResponse)
  end
end

describe Warden::Protocol::LimitCpuResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "LimitCpu" }
  its("class.type_underscored") { should == "limit_cpu" }

  it { should be_ok }
  it { should_not be_error }

  field :limit_in_shares do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end
