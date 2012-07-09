require "spec_helper"
require "warden/protocol"

describe Warden::Protocol::WrappedRequest do
  it "should respond to #request" do
    w = Warden::Protocol::WrappedRequest.new
    w.type = Warden::Protocol::Type::Ping
    w.payload = Warden::Protocol::PingRequest.new.encode
    w.should be_valid

    w.request.should be_a(Warden::Protocol::PingRequest)
  end
end

describe Warden::Protocol::WrappedResponse do
  it "should respond to #response" do
    w = Warden::Protocol::WrappedResponse.new
    w.type = Warden::Protocol::Type::Ping
    w.payload = Warden::Protocol::PingResponse.new.encode
    w.should be_valid

    w.response.should be_a(Warden::Protocol::PingResponse)
  end
end
