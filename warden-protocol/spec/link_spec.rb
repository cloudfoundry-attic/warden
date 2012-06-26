require "spec_helper"
require "warden/protocol/link"

describe Warden::Protocol::LinkRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle", :job_id => 1)
  end

  field :handle do
    it_should_be_required
    it_should_be_typed_as_string
  end

  field :job_id do
    it_should_be_required
    it_should_be_typed_as_uint
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::LinkResponse)
  end
end

describe Warden::Protocol::LinkResponse do
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
