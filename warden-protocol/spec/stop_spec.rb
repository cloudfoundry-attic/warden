# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::StopRequest do
  subject(:request) do
    Warden::Protocol::StopRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Stop')
    expect(request.class.type_underscored).to eq('stop')
  end

  field :handle do
    it_should_be_required
  end

  field :background do
    it_should_be_optional
    it_should_be_typed_as_boolean
  end

  field :kill do
    it_should_be_optional
    it_should_be_typed_as_boolean
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::StopResponse)
  end
end

describe Warden::Protocol::StopResponse do
  subject(:response) do
    Warden::Protocol::StopResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Stop')
    expect(response.class.type_underscored).to eq('stop')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end
end
