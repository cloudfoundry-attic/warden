# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::EchoRequest do
  subject(:request) do
    described_class.new(:message => "here's a snowman: ☃")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Echo" }
  its("class.type_underscored") { should == "echo" }

  field :message do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::EchoResponse)
  end
end

describe Warden::Protocol::EchoResponse do
  subject(:response) do
    described_class.new(:message => "here's a snowman: ☃")
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Echo" }
  its("class.type_underscored") { should == "echo" }

  it { should be_ok }
  it { should_not be_error }

  field :message do
    it_should_be_required
    it_should_be_typed_as_string
  end
end
