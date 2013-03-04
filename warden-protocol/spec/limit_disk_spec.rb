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
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "LimitDisk" }
  its("class.type_underscored") { should == "limit_disk" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it_should_behave_like "disk limiting"

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::LimitDiskResponse)
  end
end

describe Warden::Protocol::LimitDiskResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "LimitDisk" }
  its("class.type_underscored") { should == "limit_disk" }

  it { should be_ok }
  it { should_not be_error }

  it_should_behave_like "disk limiting"
end
