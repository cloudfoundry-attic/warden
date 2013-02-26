# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::LimitMemoryRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "LimitMemory" }
  its("class.type_underscored") { should == "limit_memory" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::LimitMemoryResponse)
  end
end

describe Warden::Protocol::LimitMemoryResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "LimitMemory" }
  its("class.type_underscored") { should == "limit_memory" }

  it { should be_ok }
  it { should_not be_error }

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end
