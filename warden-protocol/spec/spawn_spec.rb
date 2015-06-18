# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::SpawnRequest do
  subject(:request) do
    described_class.new(:handle => "handle", :script => "echo foo")
  end

  it_should_behave_like "wrappable request"

  its("class.type_camelized") { should == "Spawn" }
  its("class.type_underscored") { should == "spawn" }

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

  field :discard_output do
    it_should_be_optional
    it_should_default_to false
  end

  field :log_tag do
    it_should_be_optional
    it_should_default_to nil
  end

  it "should be populated with ResourceLimits object" do
    request.rlimits = Warden::Protocol::ResourceLimits.new
    request.should be_valid
  end

  it "should respond to #create_response" do
    request.create_response.should be_a(Warden::Protocol::SpawnResponse)
  end

  describe "filtered_hash" do
    it "excludes the script field" do
      expect(request.filtered_hash.keys).to_not include(:script)
    end
  end
end

describe Warden::Protocol::SpawnResponse do
  subject(:response) do
    described_class.new(:job_id => 1)
  end

  it_should_behave_like "wrappable response"

  its("class.type_camelized") { should == "Spawn" }
  its("class.type_underscored") { should == "spawn" }

  it { should be_ok }
  it { should_not be_error }

  field :job_id do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
