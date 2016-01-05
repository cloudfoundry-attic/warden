# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::CreateRequest do
  subject(:request) do
    Warden::Protocol::CreateRequest.new
  end

  it_should_behave_like "wrappable request"

  it 'has class type methods' do
    expect(request.class.type_camelized).to eq('Create')
    expect(request.class.type_underscored).to eq('create')
  end

  field :bind_mounts do
    it_should_be_optional

    it "should be populated with BindMount objects" do
      m = Warden::Protocol::CreateRequest::BindMount.new
      m.src_path = "/src"
      m.dst_path = "/dst"
      m.mode = Warden::Protocol::CreateRequest::BindMount::Mode::RO

      subject.bind_mounts = [m]
      expect(subject).to be_valid
    end
  end

  field :grace_time do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  field :handle do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :network do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  field :rootfs do
    it_should_be_optional
    it_should_be_typed_as_string
  end

  it "should respond to #create_response" do
    expect(request.create_response).to be_a(Warden::Protocol::CreateResponse)
  end
end

describe Warden::Protocol::CreateResponse do
  subject(:response) do
    Warden::Protocol::CreateResponse.new(:handle => "handle")
  end

  it_should_behave_like "wrappable response"

  it 'has class type methods' do
    expect(response.class.type_camelized).to eq('Create')
    expect(response.class.type_underscored).to eq('create')
  end

  it 'should be ok' do
    expect(response).to be_ok
  end

  it 'should not be an error' do
    expect(response).to_not be_error
  end

  field :handle do
    it_should_be_required
  end
end
