require "spec_helper"
require "warden/protocol/destroy"

describe Warden::Protocol::DestroyRequest do
  it_should_behave_like "wrappable request"

  subject do
    described_class.new(:handle => "handle")
  end

  its(:type_camelized) { should == "Destroy" }
  its(:type_underscored) { should == "destroy" }

  field :handle do
    it_should_be_required
  end

  it "should respond to #create_response" do
    subject.create_response.should be_a(Warden::Protocol::DestroyResponse)
  end
end

describe Warden::Protocol::DestroyResponse do
  it_should_behave_like "wrappable response"

  its(:type_camelized) { should == "Destroy" }
  its(:type_underscored) { should == "destroy" }

  it { should be_ok }
  it { should_not be_error }
end
