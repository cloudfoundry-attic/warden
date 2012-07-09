require "spec_helper"
require "warden/protocol/spawn"

describe Warden::Protocol::SpawnRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle", :script => "echo foo")
  end

  its(:type_camelized) { should == "Spawn" }
  its(:type_underscored) { should == "spawn" }

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
    subject.create_response.should be_a(Warden::Protocol::SpawnResponse)
  end
end

describe Warden::Protocol::SpawnResponse do
  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "Spawn" }
  its(:type_underscored) { should == "spawn" }

  it { should be_ok }
  it { should_not be_error }

  subject do
    described_class.new(:job_id => 1)
  end

  field :job_id do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
