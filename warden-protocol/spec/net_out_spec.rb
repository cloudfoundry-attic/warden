require "spec_helper"
require "warden/protocol/net_out"

describe Warden::Protocol::NetOutRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :network do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :port do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::NetOutResponse)
  end
end

describe Warden::Protocol::NetOutResponse do
  it_should_behave_like "wrappable response"
end
