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

  describe "parsing repl v1 arguments" do
    it "should raise for unknown arguments" do
      expect do
        Warden::Protocol::CreateReq.from_repl_v1(["unknown"])
      end.to raise_error
    end

    describe "bind_mounts" do

      describe "mode" do
        it "should parse RO mode" do
          req = Warden::Protocol::CreateReq.from_repl_v1(["bind_mount:/src,/dst,ro"])
          req.bind_mounts[0].mode.should == Warden::Protocol::CreateReq::BindMount::Mode::RO
        end

        it "should parse RW mode" do
          req = Warden::Protocol::CreateReq.from_repl_v1(["bind_mount:/src,/dst,rw"])
          req.bind_mounts[0].mode.should == Warden::Protocol::CreateReq::BindMount::Mode::RW
        end

        it "should raise when not valid" do
          expect do
            Warden::Protocol::CreateReq.from_repl_v1(["bind_mount:/src,/dst,unknown"])
          end.to raise_error
        end
      end

      it "should parse src and dst" do
        args = ["bind_mount:/src,/dst,ro"]

        req = Warden::Protocol::CreateReq.from_repl_v1(args)
        req.bind_mounts[0].src.should == "/src"
        req.bind_mounts[0].dst.should == "/dst"
      end
    end

    describe "grace_time" do
      it "should parse integer" do
        req = Warden::Protocol::CreateReq.from_repl_v1(["grace_time:37"])
        req.grace_time.should == 37
      end

      it "should raise when not valid" do
        expect do
          Warden::Protocol::CreateReq.from_repl_v1(["grace_time:unknown"])
        end.to raise_error
      end
    end
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
