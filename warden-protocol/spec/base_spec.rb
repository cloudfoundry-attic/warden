# coding: UTF-8

require "spec_helper"
require "warden/protocol"

describe Warden::Protocol::BaseRequest do
  it "should respond to #wrap" do
    request = Warden::Protocol::SpawnRequest.new(:handle => "blah",
                                                 :script => "script")
    wrapped = request.wrap
    expect(wrapped).to be_an_instance_of(Warden::Protocol::Message)
    expect(wrapped.type).to eq(Warden::Protocol::SpawnRequest.type)
    decoded = Warden::Protocol::SpawnRequest.decode(wrapped.payload)
    expect(decoded.handle).to eq(request.handle)
    expect(decoded.script).to eq(request.script)
  end

  it "should wrap beefcake errors" do
    expect {
      Warden::Protocol::SpawnRequest.new.wrap
    }.to raise_error(Warden::Protocol::ProtocolError) { |e|
      expect(e.cause.class.name).to match(/^Beefcake/)
    }
  end
end

describe Warden::Protocol::BaseResponse do
  it "should respond to #wrap" do
    response = Warden::Protocol::SpawnResponse.new(:job_id => 1)
    wrapped = response.wrap
    expect(wrapped).to be_an_instance_of(Warden::Protocol::Message)
    expect(wrapped.type).to eq(Warden::Protocol::SpawnResponse.type)
    decoded = Warden::Protocol::SpawnResponse.decode(wrapped.payload)
    expect(decoded.job_id).to eq(response.job_id)
  end

  it "should wrap beefcake errors" do
    expect {
      Warden::Protocol::SpawnResponse.new.wrap
    }.to raise_error(Warden::Protocol::ProtocolError) { |e|
      expect(e.cause.class.name).to match(/^Beefcake/)
    }
  end
end

describe "wrapped request" do
  it "should respond to #request" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = Warden::Protocol::SpawnRequest.new(:handle => "blah",
                                                   :script => "script").encode
    expect(w).to be_valid

    expect(w.request).to be_a(Warden::Protocol::SpawnRequest)
  end

  it "should wrap beefcake errors" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = "bad payload"
    expect(w).to be_valid

    expect { w.request }.to raise_error(Warden::Protocol::ProtocolError)
  end
end

describe "wrapped response" do
  it "should respond to #response" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = Warden::Protocol::SpawnResponse.new(:handle => "blah",
                                                    :job_id => 2).encode
    expect(w).to be_valid

    expect(w.response).to be_a(Warden::Protocol::SpawnResponse)
  end

  it "should wrap beefcake errors" do
    w = Warden::Protocol::Message.new
    w.type = Warden::Protocol::Message::Type::Spawn
    w.payload = "bad payload"

    expect(w).to be_valid

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
      expect(described_class.protocol_type_to_str(Test)).to eq("A, B")
    end

    it "should return string representation of symbol" do
      expect(described_class.protocol_type_to_str(:test)).to eq("test")
    end

    it "should return nil for invalid parameter" do
      expect(described_class.protocol_type_to_str(123)).to be_nil
    end
  end

  describe "#to_ruby_type" do
    it "should use the type converter if is defined" do
      allow(Warden::Protocol::TypeConverter).to receive("[]").once.
        with(:uint32).and_return(lambda { |arg| Integer(arg) } )

      expect(described_class.to_ruby_type("123", :uint32)).to eq(123)
    end

    it "should return value of constant defined in the module" do
      allow(Warden::Protocol::TypeConverter).to receive("[]").once.
        with(Test).and_return(nil)

      expect(described_class.to_ruby_type("A", Test)).to eq(1)
    end

    it "should raise an error if a constant is not defined in a module" do
      allow(Warden::Protocol::TypeConverter).to receive("[]").once.
        with(Test).and_return(nil)

      expect {
        described_class.to_ruby_type("D", Test)
      }.to raise_error { |error|
        expect(error).to be_an_instance_of TypeError
        expect(error.message).to eq("The constant: 'D' is not defined in the module: 'Test'.")
      }
    end

    it "should raise an error if protocol type is not a module and no type converter is defined" do
      allow(Warden::Protocol::TypeConverter).to receive("[]").once.
        with(:test).and_return(nil)

      expect {
        described_class.to_ruby_type("test", :test)
      }.to raise_error { |error|
        expect(error).to be_an_instance_of TypeError
        expect(error.message).to eq("Non-existent protocol type passed: 'test'.")
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
