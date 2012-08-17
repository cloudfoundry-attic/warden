# coding: UTF-8

require "spec_helper"
require "warden/protocol/net_out"

describe Warden::Protocol::NetOutRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "NetOut" }
  its("class.type_underscored") { should == "net_out" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :network do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :port do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::NetOutResponse)
  end

  it_should_behave_like "documented request"
end

describe Warden::Protocol::NetOutResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "NetOut" }
  its("class.type_underscored") { should == "net_out" }

  it { should be_ok }
  it { should_not be_error }
end
