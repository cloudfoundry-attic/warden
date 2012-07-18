# coding: UTF-8

require "spec_helper"
require "warden/protocol/copy_out"

describe Warden::Protocol::CopyOutRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(
      :handle => "handle",
      :src_path => "/src",
      :dst_path => "/dst",
    )
  end

  its(:type_camelized) { should == "CopyOut" }
  its(:type_underscored) { should == "copy_out" }

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
    subject.create_response.should be_a(Warden::Protocol::CopyOutResponse)
  end
end

describe Warden::Protocol::CopyOutResponse do
  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "CopyOut" }
  its(:type_underscored) { should == "copy_out" }

  it { should be_ok }
  it { should_not be_error }
end
