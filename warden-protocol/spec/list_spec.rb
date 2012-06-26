require "spec_helper"
require "warden/protocol/list"

describe Warden::Protocol::ListRequest do
  it_should_behave_like "wrappable request"

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::ListResponse)
  end
end

describe Warden::Protocol::ListResponse do
  it_should_behave_like "wrappable reply"

  subject do
    described_class.new
  end

  field :handles do
    it_should_be_optional

    it "should allow one or more handles" do
      subject.handles = ["a", "b"]
      subject.should be_valid
    end
  end
end
