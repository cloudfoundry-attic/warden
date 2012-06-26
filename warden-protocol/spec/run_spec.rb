require "spec_helper"
require "warden/protocol/run"

describe Warden::Protocol::RunRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle", :script => "echo foo")
  end

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
    subject.create_response.should be_a(Warden::Protocol::RunResponse)
  end
end

describe Warden::Protocol::RunResponse do
  it_should_behave_like "wrappable response"

  subject do
    described_class.new
  end

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
