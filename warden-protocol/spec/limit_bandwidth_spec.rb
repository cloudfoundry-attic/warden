# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::LimitBandwidthRequest do
  subject(:request) do
    Warden::Protocol::LimitBandwidthRequest.new(:handle => "handle", :rate => 1, :burst => 1)
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('LimitBandwidth')
    expect(request.class.type_underscored).to eq('limit_bandwidth')
  end

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
    expect(request.create_response).to be_a(Warden::Protocol::LimitBandwidthResponse)
  end
end

describe Warden::Protocol::LimitBandwidthResponse do
  subject(:response) do
    Warden::Protocol::LimitBandwidthResponse.new(:rate => 1, :burst => 1)
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('LimitBandwidth')
    expect(response.class.type_underscored).to eq('limit_bandwidth')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :rate do
    it_should_be_required
    it_should_be_typed_as_uint64
  end

  field :burst do
    it_should_be_required
    it_should_be_typed_as_uint64
  end
end
