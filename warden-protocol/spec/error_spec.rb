# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::ErrorResponse do
  subject(:response) do
    described_class.new
  end

  it_should_behave_like "wrappable response"

  it { should_not be_ok }
  it { should be_error }

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
