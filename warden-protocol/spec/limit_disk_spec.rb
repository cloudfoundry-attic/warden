# coding: UTF-8

require "spec_helper"

shared_examples "disk limiting" do
  field :block_limit do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :block do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :block_soft do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :block_hard do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :inode_limit do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :inode do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :inode_soft do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :inode_hard do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :byte_limit do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :byte do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :byte_soft do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :byte_hard do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end

describe Warden::Protocol::LimitDiskRequest do
  subject(:request) do
    Warden::Protocol::LimitDiskRequest.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('LimitDisk')
    expect(request.class.type_underscored).to eq('limit_disk')
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it_should_behave_like "disk limiting"

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::LimitDiskResponse)
  end
end

describe Warden::Protocol::LimitDiskResponse do
  subject(:response) do
    Warden::Protocol::LimitDiskResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('LimitDisk')
    expect(response.class.type_underscored).to eq('limit_disk')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  it_should_behave_like "disk limiting"
end
