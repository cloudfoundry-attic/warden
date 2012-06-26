require "spec_helper"
require "warden/protocol/limit_memory"

describe Warden::Protocol::LimitMemoryRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::LimitMemoryResponse)
  end
end

describe Warden::Protocol::LimitMemoryResponse do
  it_should_behave_like "wrappable response"

  subject do
    described_class.new
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint
  end
end
