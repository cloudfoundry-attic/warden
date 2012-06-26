require "spec_helper"
require "warden/protocol/error"

describe Warden::Protocol::ErrorResponse do
  it_should_behave_like "wrappable response"

  subject do
    described_class.new
  end

  field :message do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :data do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :backtrace do
    it_should_be_optional

    it "should allow one or more entries" do
      subject.backtrace = ["a", "b"]
      subject.should be_valid
    end
  end
end
