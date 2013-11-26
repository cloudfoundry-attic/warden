# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::CopyInRequest do
  subject(:request) do
    described_class.new(
      :handle => "handle",
      :src_path => "/src",
      :dst_path => "/dst"
    )
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "CopyIn" }
  its("class.type_underscored") { should == "copy_in" }

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

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::CopyInResponse)
  end
end

describe Warden::Protocol::CopyInResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "CopyIn" }
  its("class.type_underscored") { should == "copy_in" }

  it { should be_ok }
  it { should_not be_error }
end
