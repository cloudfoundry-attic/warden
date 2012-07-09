require "spec_helper"
require "warden/protocol/limit_memory"

describe Warden::Protocol::LimitMemoryRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  its(:type_camelized) { should == "LimitMemory" }
  its(:type_underscored) { should == "limit_memory" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::LimitMemoryResponse)
  end
end

describe Warden::Protocol::LimitMemoryResponse do
  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "LimitMemory" }
  its(:type_underscored) { should == "limit_memory" }

  it { should be_ok }
  it { should_not be_error }

  subject do
    described_class.new
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end
