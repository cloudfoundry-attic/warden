require "spec_helper"
require "warden/protocol/stop"

describe Warden::Protocol::StopRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  its(:type_camelized) { should == "Stop" }
  its(:type_underscored) { should == "stop" }

  field :handle do
    it_should_be_required
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::StopResponse)
  end
end

describe Warden::Protocol::StopResponse do
  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "Stop" }
  its(:type_underscored) { should == "stop" }

  it { should be_ok }
  it { should_not be_error }
end
