# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::SpawnRequest do
  subject(:request) do
    Warden::Protocol::SpawnRequest.new(:handle => "handle", :script => "echo foo")
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Spawn')
    expect(request.class.type_underscored).to eq('spawn')
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

  it "should be populated with ResourceLimits object" do
    request.rlimits = Warden::Protocol::ResourceLimits.new
    expect(request).to be_valid
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::SpawnResponse)
  end

  describe "filtered_hash" do
    it "excludes the script field" do
      expect(request.filtered_hash.keys).to_not include(:script)
    end
  end
end

describe Warden::Protocol::SpawnResponse do
  subject(:response) do
    Warden::Protocol::SpawnResponse.new(:job_id => 1)
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Spawn')
    expect(response.class.type_underscored).to eq('spawn')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :job_id do
    it_should_be_required
    it_should_be_typed_as_uint
  end
end
