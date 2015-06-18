# coding: UTF-8

require "spec_helper"
require "warden/protocol"

describe Warden::Protocol::BaseRequest do
  it "should respond to #wrap" do
    request = Warden::Protocol::SpawnRequest.new(:handle => "blah",
                                                 :script => "script")
    wrapped = request.wrap
    wrapped.should be_an_instance_of(Warden::Protocol::Message)
    wrapped.type.should == Warden::Protocol::SpawnRequest.type
    decoded = Warden::Protocol::SpawnRequest.decode(wrapped.payload)
    decoded.handle.should == request.handle
    decoded.script.should == request.script
  end

  it "should wrap beefcake errors" do
    expect {
      Warden::Protocol::SpawnRequest.new.wrap
    }.to raise_error(Warden::Protocol::ProtocolError) { |e|
      e.cause.class.name.should =~ /^Beefcake/
    }
  end
end

describe Warden::Protocol::BaseResponse do
  it "should respond to #wrap" do
    response = Warden::Protocol::SpawnResponse.new(:job_id => 1)
    wrapped = response.wrap
    wrapped.should be_an_instance_of(Warden::Protocol::Message)
    wrapped.type.should == Warden::Protocol::SpawnResponse.type
    decoded = Warden::Protocol::SpawnResponse.decode(wrapped.payload)
    decoded.job_id.should == response.job_id
  end

  it "should wrap beefcake errors" do
    expect {
      Warden::Protocol::SpawnResponse.new.wrap
    }.to raise_error(Warden::Protocol::ProtocolError) { |e|
      e.cause.class.name.should =~ /^Beefcake/
    }
  end
end

describe "wrapped request" do
  it "should respond to #request" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = Warden::Protocol::SpawnRequest.new(:handle => "blah",
                                                   :script => "script").encode
    w.should be_valid

    w.request.should be_a(Warden::Protocol::SpawnRequest)
  end

  it "should wrap beefcake errors" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = "bad payload"
    w.should be_valid

    expect { w.request }.to raise_error(Warden::Protocol::ProtocolError)
  end
end

describe "wrapped response" do
  it "should respond to #response" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = Warden::Protocol::SpawnResponse.new(:handle => "blah",
                                                    :job_id => 2).encode
    w.should be_valid

    w.response.should be_a(Warden::Protocol::SpawnResponse)
  end

  it "should wrap beefcake errors" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = "bad payload"

    w.should be_valid

    expect { w.response }.to raise_error(Warden::Protocol::ProtocolError)
  end
end

describe Warden::Protocol do
  before :all do
    module Test
      B = 2
      A = 1
    end
  end

  describe "#protocol_type_to_str" do
    it "should return string representation of constants in a module" do
      described_class.protocol_type_to_str(Test).should == "A, B"
    end

    it "should return string representation of symbol" do
      described_class.protocol_type_to_str(:test).should == "test"
    end

    it "should return nil for invalid parameter" do
      described_class.protocol_type_to_str(123).should be_nil
    end
  end

  describe "#to_ruby_type" do
    it "should use the type converter if is defined" do
      Warden::Protocol::TypeConverter.should_receive("[]").once.
        with(:uint32).and_return(lambda { |arg| Integer(arg) } )

      described_class.to_ruby_type("123", :uint32).should == 123
    end

    it "should return value of constant defined in the module" do
      Warden::Protocol::TypeConverter.should_receive("[]").once.
        with(Test).and_return(nil)

      described_class.to_ruby_type("A", Test).should == 1
    end

    it "should raise an error if a constant is not defined in a module" do
      Warden::Protocol::TypeConverter.should_receive("[]").once.
        with(Test).and_return(nil)

      expect {
        described_class.to_ruby_type("D", Test)
      }.to raise_error { |error|
        error.should be_an_instance_of TypeError
        error.message.should == "The constant: 'D' is not defined in the module: 'Test'."
      }
    end

    it "should raise an error if protocol type is not a module and no type converter is defined" do
      Warden::Protocol::TypeConverter.should_receive("[]").once.
        with(:test).and_return(nil)

      expect {
        described_class.to_ruby_type("test", :test)
      }.to raise_error { |error|
        error.should be_an_instance_of TypeError
        error.message.should == "Non-existent protocol type passed: 'test'."
      }
    end
  end
end

describe Warden::Protocol::BaseMessage do
  class TestMessage
    include Warden::Protocol::BaseMessage

    required :field1, :string, 1
    required :field2, :string, 2

    def filtered_fields
      [:field2]
    end
  end

  describe "filtered_hash" do
    it "filters out the filtered_fields" do
      message = TestMessage.new(field1: 'f1', field2: 'f2')
      expect(message.filtered_hash.keys).to_not include(:field2)
    end
  end
end