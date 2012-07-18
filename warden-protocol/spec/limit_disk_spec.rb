# coding: UTF-8

require "spec_helper"
require "warden/protocol/limit_disk"

describe Warden::Protocol::LimitDiskRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its(:type_camelized) { should == "LimitDisk" }
  its(:type_underscored) { should == "limit_disk" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :block_limit do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  field :inode_limit do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::LimitDiskResponse)
  end
end

describe Warden::Protocol::LimitDiskResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "LimitDisk" }
  its(:type_underscored) { should == "limit_disk" }

  it { should be_ok }
  it { should_not be_error }

  field :block_limit do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  field :inode_limit do
    it_should_be_optional
    it_should_be_typed_as_uint
  end
end
