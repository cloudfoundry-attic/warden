# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::NetInRequest do
  subject(:request) do
    Warden::Protocol::NetInRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('NetIn')
    expect(request.class.type_underscored).to eq('net_in')
  end

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
    expect(request.create_response).to be_a(Warden::Protocol::NetInResponse)
  end
end

describe Warden::Protocol::NetInResponse do
  subject(:response) do
    Warden::Protocol::NetInResponse.new(:host_port => 1234, :container_port => 1234)
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('NetIn')
    expect(response.class.type_underscored).to eq('net_in')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :host_port do
    it_should_be_required
    it_should_be_typed_as_uint
  end

  field :container_port do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
