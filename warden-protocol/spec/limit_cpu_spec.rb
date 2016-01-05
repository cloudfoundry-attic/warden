# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::LimitCpuRequest do
  subject(:request) do
    Warden::Protocol::LimitCpuRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('LimitCpu')
    expect(request.class.type_underscored).to eq('limit_cpu')
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :limit_in_shares do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::LimitCpuResponse)
  end
end

describe Warden::Protocol::LimitCpuResponse do
  subject(:response) do
    Warden::Protocol::LimitCpuResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('LimitCpu')
    expect(response.class.type_underscored).to eq('limit_cpu')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :limit_in_shares do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end
