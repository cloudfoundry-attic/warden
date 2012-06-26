require "spec_helper"
require "warden/protocol/ping"

describe Warden::Protocol::PingReq do
  it_should_behave_like "wrappable request"

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::PingRep)
  end
end

describe Warden::Protocol::PingRep do
  it_should_behave_like "wrappable reply"
end
