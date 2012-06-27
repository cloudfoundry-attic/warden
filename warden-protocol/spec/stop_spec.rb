require "spec_helper"
require "warden/protocol/stop"

describe Warden::Protocol::StopRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  field :handle do
    it_should_be_required
  end

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::StopResponse)
  end
end

describe Warden::Protocol::StopResponse do
  it_should_behave_like "wrappable reply"
end
