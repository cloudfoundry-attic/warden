require "spec_helper"
require "warden/protocol/stream"

describe Warden::Protocol::StreamRequest do
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
    subject.create_response.should be_a(Warden::Protocol::StreamResponse)
  end
end

describe Warden::Protocol::StreamResponse do
  it_should_behave_like "wrappable response"

  it { should be_ok }
  it { should_not be_error }

  subject do
    described_class.new
  end

  field :name do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :data do
    it_should_be_optional
    it_should_be_typed_as_string
  end
end
