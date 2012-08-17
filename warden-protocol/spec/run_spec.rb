# coding: UTF-8

require "spec_helper"
require "warden/protocol/run"

describe Warden::Protocol::RunRequest do
  subject(:request) do
    described_class.new(:handle => "handle", :script => "echo foo")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Run" }
  its("class.type_underscored") { should == "run" }

  field :handle do
    it_should_be_required
  end

  field :script do
    it_should_be_required
  end

  field :privileged do
    it_should_be_optional
    it_should_default_to false
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::RunResponse)
  end

  it_should_behave_like "documented request"
end

describe Warden::Protocol::RunResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Run" }
  its("class.type_underscored") { should == "run" }

  it { should be_ok }
  it { should_not be_error }

  field :exit_status do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  field :stdout do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :stderr do
    it_should_be_optional
    it_should_be_typed_as_string
  end
end
