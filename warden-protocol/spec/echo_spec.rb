# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::EchoRequest do
  subject(:request) do
    Warden::Protocol::EchoRequest.new(:message => "here's a snowman: ☃")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Echo')
    expect(request.class.type_underscored).to eq('echo')
  end

  field :message do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::EchoResponse)
  end
end

describe Warden::Protocol::EchoResponse do
  subject(:response) do
    Warden::Protocol::EchoResponse.new(:message => "here's a snowman: ☃")
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Echo')
    expect(response.class.type_underscored).to eq('echo')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :message do
    it_should_be_required
    it_should_be_typed_as_string
  end
end
