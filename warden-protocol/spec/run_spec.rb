# coding: UTF-8

require "spec_helper"

module Warden::Protocol
  describe RunRequest do
    subject(:request) do
      Warden::Protocol::RunRequest.new(:handle => "handle", :script => "echo foo")
    end

    it_should_behave_like "wrappable request"

    it 'has class type methods' do
      expect(request.class.type_camelized).to eq('Run')
      expect(request.class.type_underscored).to eq('run')
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

    field :discard_output do
      it_should_be_optional
      it_should_default_to false
    end

    field :log_tag do
      it_should_be_optional
      it_should_default_to nil
    end

    field :rlimits do
      it_should_be_optional

      it "should be populated with ResourceLimits object" do
        request.rlimits = ResourceLimits.new
        expect(request).to be_valid
      end
    end

    it "should respond to #create_response" do
      expect(request.create_response).to be_a(RunResponse)
    end
  end

  describe RunResponse do
    subject(:response) do
      Warden::Protocol::RunResponse.new
    end

    it_should_behave_like "wrappable response"

    it 'has class type methods' do
      expect(response.class.type_camelized).to eq('Run')
      expect(response.class.type_underscored).to eq('run')
    end

    it 'should be ok' do
      expect(response).to be_ok
    end

    it 'should not be an error' do
      expect(response).to_not be_error
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

    field :info do
      it_should_be_optional

      it "should be a InfoResponse" do
        expect(field.type).to eq(InfoResponse)
      end
    end
  end
end
