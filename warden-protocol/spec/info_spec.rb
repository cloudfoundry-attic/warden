require "spec_helper"
require "warden/protocol/info"

describe Warden::Protocol::InfoRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::InfoResponse)
  end
end

describe Warden::Protocol::InfoResponse do
  it_should_behave_like "wrappable response"

  subject do
    described_class.new
  end

  field :state do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :events do
    it_should_be_optional

    it "should allow one or more events" do
      subject.events = ["a", "b"]
      subject.should be_valid
    end
  end

  field :host_ip do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :container_ip do
    it_should_be_optional
    it_should_be_typed_as_string
  end
end
