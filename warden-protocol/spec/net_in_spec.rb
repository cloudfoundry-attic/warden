# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::NetInRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "NetIn" }
  its("class.type_underscored") { should == "net_in" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :container_port do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  field :host_port do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::NetInResponse)
  end
end

describe Warden::Protocol::NetInResponse do
  subject(:response) do
    described_class.new(:host_port => 1234, :container_port => 1234)
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "NetIn" }
  its("class.type_underscored") { should == "net_in" }

  it { should be_ok }
  it { should_not be_error }

  field :host_port do
    it_should_be_required
    it_should_be_typed_as_uint
  end

  field :container_port do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
