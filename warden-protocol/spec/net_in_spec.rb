require "spec_helper"
require "warden/protocol/net_in"

describe Warden::Protocol::NetInReq do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :container_port do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::NetInRep)
  end
end

describe Warden::Protocol::NetInRep do
  it_should_behave_like "wrappable reply"

  subject do
    described_class.new(:host_port => 1234, :container_port => 1234)
  end

  field :host_port do
    it_should_be_required
    it_should_be_typed_as_uint
  end

  field :container_port do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
