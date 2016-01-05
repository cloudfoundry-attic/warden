# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::PingRequest do
  subject(:request) do
    Warden::Protocol::PingRequest.new
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Ping')
    expect(request.class.type_underscored).to eq('ping')
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::PingResponse)
  end
end

describe Warden::Protocol::PingResponse do
  subject(:response) do
    Warden::Protocol::PingResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Ping')
    expect(response.class.type_underscored).to eq('ping')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end
end
