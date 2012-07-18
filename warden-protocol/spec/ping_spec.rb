# coding: UTF-8

require "spec_helper"
require "warden/protocol/ping"

describe Warden::Protocol::PingRequest do
  it_should_behave_like "wrappable request"

  its(:type_camelized) { should == "Ping" }
  its(:type_underscored) { should == "ping" }

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::PingResponse)
  end
end

describe Warden::Protocol::PingResponse do
  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "Ping" }
  its(:type_underscored) { should == "ping" }

  it { should be_ok }
  it { should_not be_error }
end
