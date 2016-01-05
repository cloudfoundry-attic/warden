# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::LimitMemoryRequest do
  subject(:request) do
    Warden::Protocol::LimitMemoryRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('LimitMemory')
    expect(request.class.type_underscored).to eq('limit_memory')
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::LimitMemoryResponse)
  end
end

describe Warden::Protocol::LimitMemoryResponse do
  subject(:response) do
    Warden::Protocol::LimitMemoryResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('LimitMemory')
    expect(response.class.type_underscored).to eq('limit_memory')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :limit_in_bytes do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end
