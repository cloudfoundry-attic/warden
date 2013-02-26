# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::DestroyRequest do
  subject(:request) do
    described_class.new(:handle => "handle")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Destroy" }
  its("class.type_underscored") { should == "destroy" }

  field :handle do
    it_should_be_required
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::DestroyResponse)
  end
end

describe Warden::Protocol::DestroyResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Destroy" }
  its("class.type_underscored") { should == "destroy" }

  it { should be_ok }
  it { should_not be_error }
end
