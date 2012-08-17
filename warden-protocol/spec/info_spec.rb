# coding: UTF-8

require "spec_helper"
require "warden/protocol/info"

describe Warden::Protocol::InfoRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Info" }
  its("class.type_underscored") { should == "info" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::InfoResponse)
  end

  it_should_behave_like "documented request"
end

describe Warden::Protocol::InfoResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Info" }
  its("class.type_underscored") { should == "info" }

  it { should be_ok }
  it { should_not be_error }

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
