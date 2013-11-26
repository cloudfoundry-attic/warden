# coding: UTF-8

require "spec_helper"
require "warden/protocol/buffer"

describe Warden::Protocol::Buffer do
  let(:request) { Warden::Protocol::EchoRequest.new(:message => "request") }
  let(:response) { Warden::Protocol::EchoResponse.new(:message => "response") }

  subject { described_class.new }

  it "should support iterating over requests" do
    subject << Warden::Protocol::Buffer.request_to_wire(request)
    subject.each_request do |request|
      request.class.should == Warden::Protocol::EchoRequest
      request.message.should == "request"
    end
  end

  it "should support iterating over responses" do
    subject << Warden::Protocol::Buffer.response_to_wire(response)
    subject.each_response do |response|
      response.class.should == Warden::Protocol::EchoResponse
      response.message.should == "response"
    end
  end

  describe "fuzzing" do
    it "should not break request iteration" do
      data = Warden::Protocol::Buffer.request_to_wire(request)

      loop do
        chunk = data.slice!(0).chr
        subject << chunk
        break if data.empty?

        subject.each_request do
          fail
        end
      end

      subject.each_request do |request|
        request.class.should == Warden::Protocol::EchoRequest
        request.message.should == "request"
      end
    end

    it "should not break response iteration" do
      data = Warden::Protocol::Buffer.response_to_wire(response)

      loop do
        chunk = data.slice!(0).chr
        subject << chunk
        break if data.empty?

        subject.each_response do
          fail
        end
      end

      subject.each_response do |response|
        response.class.should == Warden::Protocol::EchoResponse
        response.message.should == "response"
      end
    end
  end
end
