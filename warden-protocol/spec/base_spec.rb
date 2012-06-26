require "spec_helper"
require "warden/protocol"

describe Warden::Protocol::WrappedReq do
  it "should respond to #request" do
    w = Warden::Protocol::WrappedReq.new
    w.type = Warden::Protocol::Type::Ping
    w.payload = Warden::Protocol::PingReq.new.encode
    w.should be_valid

    w.request.should be_a(Warden::Protocol::PingReq)
  end
end

describe Warden::Protocol::WrappedRep do
  it "should respond to #reply" do
    w = Warden::Protocol::WrappedRep.new
    w.type = Warden::Protocol::Type::Ping
    w.payload = Warden::Protocol::PingRep.new.encode
    w.should be_valid

    w.reply.should be_a(Warden::Protocol::PingRep)
  end
end
