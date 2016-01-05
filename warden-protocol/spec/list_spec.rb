# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::ListRequest do
  subject(:request) do
    Warden::Protocol::ListRequest.new
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('List')
    expect(request.class.type_underscored).to eq('list')
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::ListResponse)
  end
end

describe Warden::Protocol::ListResponse do
  subject(:response) do
    Warden::Protocol::ListResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('List')
    expect(response.class.type_underscored).to eq('list')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :handles do
    it_should_be_optional

    it "should allow one or more handles" do
      subject.handles = ["a", "b"]
      expect(subject).to be_valid
    end
  end
end
