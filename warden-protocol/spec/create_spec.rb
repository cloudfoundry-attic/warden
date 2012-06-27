require "spec_helper"
require "warden/protocol/create"

describe Warden::Protocol::CreateReq do
  it_should_behave_like "wrappable request"

  field :bind_mounts do
    it_should_be_optional

    it "should be populated with BindMount objects" do
      m = Warden::Protocol::CreateReq::BindMount.new
      m.src = "/src"
      m.dst = "/dst"
      m.mode = Warden::Protocol::CreateReq::BindMount::Mode::RO

      subject.bind_mounts = [m]
      subject.should be_valid
    end
  end

  field :grace_time do
    it_should_be_optional
    it_should_be_typed_as_uint
  end

  it "should respond to #create_reply" do
    subject.create_reply.should be_a(Warden::Protocol::CreateRep)
  end
end

describe Warden::Protocol::CreateRep do
  it_should_behave_like "wrappable reply"

  subject do
    described_class.new(:handle => "handle")
  end

  field :handle do
    it_should_be_required
  end
end
