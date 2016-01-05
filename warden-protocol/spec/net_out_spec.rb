# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::NetOutRequest do
  subject(:request) do
    Warden::Protocol::NetOutRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('NetOut')
    expect(request.class.type_underscored).to eq('net_out')
  end

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

  field :log do
    it_should_be_optional
    it_should_be_typed_as_boolean
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::NetOutResponse)
  end
end

describe Warden::Protocol::NetOutResponse do
  subject(:response) do
    Warden::Protocol::NetOutResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('NetOut')
    expect(response.class.type_underscored).to eq('net_out')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end
end
