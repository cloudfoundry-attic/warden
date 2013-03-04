# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::LimitBandwidthRequest do
  subject(:request) do
    described_class.new(:handle => "handle", :rate => 1, :burst => 1)
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "LimitBandwidth" }
  its("class.type_underscored") { should == "limit_bandwidth" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :rate do
    it_should_be_required
    it_should_be_typed_as_uint64
  end

  field :burst do
    it_should_be_required
    it_should_be_typed_as_uint64
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::LimitBandwidthResponse)
  end
end

describe Warden::Protocol::LimitBandwidthResponse do
  subject(:response) do
    described_class.new(:rate => 1, :burst => 1)
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "LimitBandwidth" }
  its("class.type_underscored") { should == "limit_bandwidth" }

  it { should be_ok }
  it { should_not be_error }

  field :rate do
    it_should_be_required
    it_should_be_typed_as_uint64
  end

  field :burst do
    it_should_be_required
    it_should_be_typed_as_uint64
  end
end
