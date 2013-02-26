# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::StopRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Stop" }
  its("class.type_underscored") { should == "stop" }

  field :handle do
    it_should_be_required
  end

  field :background do
    it_should_be_optional
    it_should_be_typed_as_boolean
  end

  field :kill do
    it_should_be_optional
    it_should_be_typed_as_boolean
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::StopResponse)
  end
end

describe Warden::Protocol::StopResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Stop" }
  its("class.type_underscored") { should == "stop" }

  it { should be_ok }
  it { should_not be_error }
end
