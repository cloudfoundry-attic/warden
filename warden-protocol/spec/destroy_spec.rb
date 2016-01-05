# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::DestroyRequest do
  subject(:request) do
    Warden::Protocol::DestroyRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Destroy')
    expect(request.class.type_underscored).to eq('destroy')
  end

  field :handle do
    it_should_be_required
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::DestroyResponse)
  end
end

describe Warden::Protocol::DestroyResponse do
  subject(:response) do
    Warden::Protocol::DestroyResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Destroy')
    expect(response.class.type_underscored).to eq('destroy')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end
end
