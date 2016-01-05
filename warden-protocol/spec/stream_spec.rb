# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::StreamRequest do
  subject(:request) do
    Warden::Protocol::StreamRequest.new(:handle => "handle", :job_id => 1)
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Stream')
    expect(request.class.type_underscored).to eq('stream')
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :job_id do
    it_should_be_required
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::StreamResponse)
  end
end

describe Warden::Protocol::StreamResponse do
  subject(:response) do
    Warden::Protocol::StreamResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Stream')
    expect(response.class.type_underscored).to eq('stream')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :name do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :data do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :exit_status do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  field :info do
    it_should_be_optional

    it "should be a InfoResponse" do
      expect(field.type).to eq(Warden::Protocol::InfoResponse)
    end
  end
end
