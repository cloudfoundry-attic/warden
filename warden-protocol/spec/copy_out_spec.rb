# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::CopyOutRequest do
  subject(:request) do
    Warden::Protocol::CopyOutRequest.new(
      :handle => "handle",
      :src_path => "/src",
      :dst_path => "/dst"
    )
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('CopyOut')
    expect(request.class.type_underscored).to eq('copy_out')
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :src_path do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :dst_path do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :owner do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::CopyOutResponse)
  end
end

describe Warden::Protocol::CopyOutResponse do
  subject(:response) do
    Warden::Protocol::CopyOutResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('CopyOut')
    expect(response.class.type_underscored).to eq('copy_out')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end
end
