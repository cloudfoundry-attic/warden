require "spec_helper"
require "warden/protocol/net_out"

describe Warden::Protocol::NetOutReq do
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

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::NetOutRep)
  end
end

describe Warden::Protocol::NetOutRep do
  it_should_behave_like "wrappable reply"
end
