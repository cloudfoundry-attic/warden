require "spec_helper"
require "warden/protocol/ping"

describe Warden::Protocol::PingRequest do
  it_should_behave_like "wrappable request"

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::PingResponse)
  end
end

describe Warden::Protocol::PingResponse do
  it_should_behave_like "wrappable reply"
end
