# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::ErrorResponse do
  subject(:response) do
    Warden::Protocol::ErrorResponse.new
  end

  it_should_behave_like "wrappable response"

  it 'should not be ok' do
    expect(response).to_not be_ok
  end

  it 'should be an error' do
    expect(response).to be_error
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
      expect(subject).to be_valid
    end
  end
end
