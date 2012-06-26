require "spec_helper"
require "warden/protocol/spawn"

describe Warden::Protocol::SpawnReq do
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

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::SpawnRep)
  end
end

describe Warden::Protocol::SpawnRep do
  it_should_behave_like "wrappable reply"

  subject do
    described_class.new(:job_id => 1)
  end

  field :job_id do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
