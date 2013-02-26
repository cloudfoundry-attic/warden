# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::PingRequest do
  subject(:request) do
    described_class.new
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Ping" }
  its("class.type_underscored") { should == "ping" }

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::PingResponse)
  end
end

describe Warden::Protocol::PingResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Ping" }
  its("class.type_underscored") { should == "ping" }

  it { should be_ok }
  it { should_not be_error }
end
