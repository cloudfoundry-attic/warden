# coding: UTF-8

require "spec_helper"
require "warden/protocol/detach_image"

describe Warden::Protocol::DetachImageRequest do
  subject(:request) do
    described_class.new(:handle => "handle", :image_path => "/10M.img")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "DetachImage" }
  its("class.type_underscored") { should == "detach_image" }

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :image_path do
    it_should_be_required
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::DetachImageResponse)
  end

  it_should_behave_like "documented request"
end

describe Warden::Protocol::DetachImageResponse do
  subject(:response) do
    described_class.new(:exit_status => 0)
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "DetachImage" }
  its("class.type_underscored") { should == "detach_image" }

  it { should be_ok }
  it { should_not be_error }

  field :exit_status do
    it_should_be_required
    it_should_be_typed_as_uint
  end

  field :message do
    it_should_be_optional
    it_should_be_typed_as_string
  end

end
