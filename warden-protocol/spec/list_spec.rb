# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::ListRequest do
  subject(:request) do
    described_class.new
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "List" }
  its("class.type_underscored") { should == "list" }

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::ListResponse)
  end
end

describe Warden::Protocol::ListResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "List" }
  its("class.type_underscored") { should == "list" }

  it { should be_ok }
  it { should_not be_error }

  field :handles do
    it_should_be_optional

    it "should allow one or more handles" do
      subject.handles = ["a", "b"]
      subject.should be_valid
    end
  end
end
