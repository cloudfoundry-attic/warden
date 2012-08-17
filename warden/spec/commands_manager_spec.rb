# coding: UTF-8

require "warden/commands_manager"
require "warden/protocol"

class SimpleTest < Warden::Protocol::BaseRequest
  required :field, :string, 1

  def self.description
    "Simple test command."
  end
end

class RepeatedTest < Warden::Protocol::BaseRequest
  repeated :field, :string, 1

  def self.description
    "Repeated test command."
  end
end

class NestedTest < Warden::Protocol::BaseRequest
  required :complex_field, SimpleTest, 1

  def self.description
    "Nested test command."
  end
end

class BoolTest < Warden::Protocol::BaseRequest
  required :field, :bool, 1

  def self.description
    "Bool test command."
  end
end

class MixedTest < Warden::Protocol::BaseRequest
  repeated :complex_field, SimpleTest, 1
  required :bool_field, :bool, 2

  def self.description
    "Mixed test command."
  end
end

class EnumTest < Warden::Protocol::BaseRequest
  module Enum
    A = 1
    B = 2
  end

  required :field, Enum, 1

  def self.description
    "Enum test command."
  end
end

class BadEnumTest < Warden::Protocol::BaseRequest
  module BadEnum
    A = 1
    B = 1 # two enum constants can't have the same value.
  end

  required :field, BadEnum, 1

  def self.description
    "Bad enum test command."
  end
end

class WrongTypeTest < Warden::Protocol::BaseRequest
  required :int_field, :uint32, 1

  def self.description
    "Wrong type test command."
  end
end

class SimpleFieldsHelpTest < Warden::Protocol::BaseRequest
  required :req_field, :string, 1
  repeated :rep_field, :uint32, 2
  optional :opt_field, :string, 3, :default => "default_value"
  required :req_bool_field, :bool, 4

  def self.description
    "Command to test generation of help for simple fields."
  end
end

class NestedFieldsHelpTest < Warden::Protocol::BaseRequest
  required :req_complex_field, SimpleFieldsHelpTest, 1

  def self.description
    "Command to test generation of help for nested field."
  end
end

def test_klass_map
  {
    1 => SimpleTest,
    2 => RepeatedTest,
    3 => NestedTest,
    4 => BoolTest,
    5 => EnumTest,
    6 => MixedTest,
    7 => BadEnumTest,
    8 => WrongTypeTest,
    9 => SimpleFieldsHelpTest,
    10 => NestedFieldsHelpTest,
  }
end

def test_desc_map
  test_desc_map = {}
  test_klass_map.each_pair do |k, type|
    test_desc_map[type.type_underscored] = type.description
  end

  test_desc_map
end

describe Warden::CommandsManager::FlagElement do
  before :each do
    @klass = Warden::CommandsManager::FlagElement
  end

  describe "#new" do
    it "should raise an error when a non-string object is passed" do
      expect {
        @klass.new(Object.new)
      }.to raise_error{ |error|
        error.should be_an_instance_of ArgumentError
        error.message.should == "Expected argument to be of type: #{String}, but received: #{Object}."
      }
    end

    it "should raise an error when the flag element string is malformed" do
      expect {
        @klass.new("%")
      }.to raise_error { |error|
        error.should be_an_instance_of Warden::CommandsManager::FlagElementError
        error.message.should == "Invalid flag element: '%'."
      }

      expect {
        @klass.new("0")
      }.to raise_error { |error|
        error.should be_an_instance_of Warden::CommandsManager::FlagElementError
        error.message.should == "Invalid flag element: '0'."
      }
    end
  end


  describe "#name, #index" do
    it "should parse the field name and index from a valid flag element string" do
      obj = @klass.new("field")
      obj.name.should == "field"
      obj.index.should be_nil

      obj = @klass.new("field[0]")
      obj.name.should == "field"
      obj.index.should == 0
    end
  end

  describe "#to_s" do
    it "should return the string representation" do
      @klass.new("field").to_s.should == "field"
      @klass.new("field[0]").to_s.should == "field[0]"
    end
  end

  describe "#==" do
    it "should return false for nil" do
      (@klass.new("a[0]") == nil).should be_false
    end

    it "should return false for different class type" do
      (@klass.new("a[0]") == Object.new).should be_false
    end

    it "should return false if attributes are different" do
      (@klass.new("a[0]") == @klass.new("b[1]")).should be_false
    end

    it "should return true if attribtues are the same" do
      (@klass.new("a[0]") == @klass.new("a[0]")).should be_true
    end
  end
end

describe Warden::CommandsManager::Flag do
  before :each do
    @klass = Warden::CommandsManager::Flag
  end

  describe "#new" do
    it "should raise an error when a non-string object is passed" do
      expect {
        @klass.new(Object.new)
      }.to raise_error{ |error|
        error.should be_an_instance_of ArgumentError
        error.message.should == "Expected argument to be of type: #{String}, but received: #{Object}."
      }
    end

    it "should raise an error when the flag string is malformed" do
      expect {
        @klass.new("blah")
      }.to raise_error{ |error|
        error.should be_an_instance_of Warden::CommandsManager::FlagError
        error.message.should == "Invalid flag: 'blah'."
      }
    end

    it "should raise an error when an element of the flag string is malformed" do
      expect {
        @klass.new("--blah[0].-$%.foo.bar")
      }.to raise_error { |error|
        error.should be_an_instance_of Warden::CommandsManager::FlagError
        error.message.should == "In flag: '--blah[0].-$%.foo.bar', Invalid flag element: '-$%'."
      }
    end
  end

  describe "#each" do
    it "should allow iteration over flag elements" do
      elements = [Warden::CommandsManager::FlagElement.new("a[0]"),
                  Warden::CommandsManager::FlagElement.new("b")]
      obj = @klass.new("--#{elements[0].to_s}.#{elements[1].to_s}")

      obj.respond_to?(:each).should be_true
      index = 0
      obj.each do |element|
        element.should be_an_instance_of Warden::CommandsManager::FlagElement
        element.should == elements[index]
        index += 1
      end

      obj.respond_to?(:each_with_index).should be_true
      obj.each_with_index do |element, index|
        element.should be_an_instance_of Warden::CommandsManager::FlagElement
        element.should == elements[index]
      end
    end
  end
end

describe Warden::CommandsManager do
  before :each do
    @subject = Object.new
    @subject.extend(Warden::CommandsManager)
  end

  describe "#deserialize" do
    it "should allow global help flag" do
      args = ["--help"]
      type, obj = @subject.deserialize(args)
      type.should == :help
      obj.should be_nil

      args = ["help"]
      type, obj = @subject.deserialize(args)
      type.should == :help
      obj.should be_nil
    end

    context "parse valid fields" do
      before :each do
        @request = nil
        Warden::Protocol::Type.should_receive(:generate_klass_map).
          with("Request").and_return(test_klass_map)
      end

      after :each do
        expect { @request.encode }.to_not raise_error if @request
      end

      it "should parse simple field" do
        args = ["simple_test",
                "--field", "value"]
        type, @request = @subject.deserialize(args)
        type.should == :simple_test
        @request.should be_an_instance_of SimpleTest
        @request.field.should == "value"
      end

      it "should parse repeated field" do
        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[1]", "value_1"]
        type, @request = @subject.deserialize(args)
        type.should == :repeated_test
        @request.should be_an_instance_of RepeatedTest
        @request.field.size.should == 2
        @request.field[0].should == "value_0"
        @request.field[1].should == "value_1"
      end

      it "should parse nested field" do
        args  = ["nested_test",
                 "--complex_field.field", "value"]
        type, @request = @subject.deserialize(args)
        type.should == :nested_test
        @request.should be_an_instance_of NestedTest
        @request.complex_field.field.should == "value"
      end

      it "should parse bool field" do
        args = ["bool_test",
                "--field"]
        type, @request = @subject.deserialize(args)
        type.should == :bool_test
        @request.should be_an_instance_of BoolTest
        @request.field.should be_true
      end

      it "should parse enum field" do
        args = ["enum_test",
                "--field", "A"]
        type, @request = @subject.deserialize(args)
        type.should == :enum_test
        @request.should be_an_instance_of EnumTest
        @request.field.should == EnumTest::Enum::A
      end

      it "should parse mixed fields" do
        args = ["mixed_test",
               "--bool_field",
               "--complex_field[0].field", "value"]
        type, @request = @subject.deserialize(args)
        type.should == :mixed_test
        @request.should be_an_instance_of MixedTest
        @request.complex_field.should be_an_instance_of Array
        @request.complex_field.size.should == 1
        @request.complex_field[0].should be_an_instance_of SimpleTest
        @request.complex_field[0].field.should == "value"
        @request.bool_field.should == true
      end

      it "should allow overwriting of simple field" do
        args = ["simple_test",
                "--field", "value",
                "--field", "overwrite"]
        type, @request = @subject.deserialize(args)
        type.should == :simple_test
        @request.should be_an_instance_of SimpleTest
        @request.field.should == "overwrite"
      end

      it "should allow overwriting of repeated field" do
        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[0]", "overwrite"]
        type, @request = @subject.deserialize(args)
        type.should == :repeated_test
        @request.should be_an_instance_of RepeatedTest
        @request.field.size.should == 1
        @request.field[0].should == "overwrite"
      end

      it "should allow overwriting of nested field" do
        args  = ["nested_test",
                 "--complex_field.field", "value",
                 "--complex_field.field", "overwrite"]
        type, @request = @subject.deserialize(args)
        type.should == :nested_test
        @request.should be_an_instance_of NestedTest
        @request.complex_field.should be_an_instance_of SimpleTest
        @request.complex_field.field.should == "overwrite"
      end

      it "should allow overwriting of bool field" do
        args  = ["bool_test",
                 "--field",
                 "--field"]
        type, @request = @subject.deserialize(args)
        type.should == :bool_test
        @request.should be_an_instance_of BoolTest
        @request.field.should be_true
      end

      it "should allow overwriting of enum field" do
        args = ["enum_test",
                "--field", "A",
                "--field", "B"]
        type, @request = @subject.deserialize(args)
        type.should == :enum_test
        @request.should be_an_instance_of EnumTest
        @request.field.should == EnumTest::Enum::B
      end

      it "should work for a different field delimiter" do
        args = ["nested_test",
                "--complex_field:field", "value"]
        type, @request = @subject.deserialize(args,
                                              ":")
        type.should == :nested_test
        @request.should be_an_instance_of NestedTest
        @request.complex_field.field.should == "value"
      end
    end

    context "reject invalid commands and fields" do
      before :each do
        Warden::Protocol::Type.should_receive(:generate_klass_map).
          with("Request").and_return(test_klass_map)
      end

      it "should raise an error when command is bad" do
        args = ["absent_command"]

        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::CommandError
          error.message.should == "Command: 'absent_command' is non-existent."
        }
      end

      it "should raise an error when bad help field is specified" do
        args = ["simple_fields_help_test",
                "help"]

        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'help'."
        }
      end

      it "should raise an error when simple field is bad" do
        args = ["simple_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'field'."
        }

        args = ["simple_test",
                "--field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: '--field'."
        }

        args = ["simple_test",
                "--bad_field", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--bad_field', the field: 'bad_field' is invalid."
        }
      end

      it "should raise error when repeated field is bad" do
        args = ["repeated_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'field'."
        }

        args = ["repeated_test",
                "--field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--field', the field: 'field' is not indexed."
        }

        args = ["repeated_test",
                "--field[1]", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--field[1]', the field: 'field[1]' is not indexed correctly."
        }

        args = ["repeated_test",
                "--field[bad_index]", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--field[bad_index]', Invalid flag element: 'field[bad_index]'."
        }

        args = ["repeated_test",
                "--field[-1]", "value_0"]

        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--field[-1]', Invalid flag element: 'field[-1]'."
        }

        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[2]", "value_2"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--field[2]', the field: 'field[2]' is not indexed correctly."
        }
      end

      it "should raise an error when nested field is bad" do
        args = ["nested_test",
                "complex_field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'complex_field'."
        }

        args = ["nested_test",
                "--complex_field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: '--complex_field'."
        }

        args = ["nested_test",
                "--complex_field.absent_field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--complex_field.absent_field', the field: 'absent_field' is invalid."
        }

        args = ["nested_test",
                "--complex_field.field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: '--complex_field.field'."
        }
      end

      it "should raise an error when bool field is bad" do
        args = ["bool_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'field'."
        }

        args = ["bool_test",
                "--field", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'value'."
        }
      end

      it "should raise an error when enum field is bad" do
        args = ["enum_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: 'field'."
        }

        args = ["enum_test",
                "--field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "Invalid flag: '--field'."
        }

        args = ["enum_test",
                "--bad_field", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of Warden::CommandsManager::FlagError
          error.message.should == "In flag: '--bad_field', the field: 'bad_field' is invalid."
        }
      end

      it "should raise an error when wrong type is passed" do
        args = ["wrong_type_test",
                "--int_field", "blah"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          error.should be_an_instance_of ArgumentError
          error.message.should == "invalid value for Integer(): \"blah\""
        }
      end
    end

    context "generate help" do

      before(:each) do
        Warden::Protocol::Type.should_receive(:generate_klass_map).once.
          with("Request").and_return(test_klass_map)
      end

      it "should generate help for a command with simple field(s)" do
        args = ["simple_fields_help_test",
                "--help"]
        type, help = @subject.deserialize(args)
        type.should == :command_help
        help.should be_an_instance_of Hash
        help.should == {
          :simple_fields_help_test => {
            :description => "Command to test generation of help for simple fields.",
            :required => {
              :req_field => "--req_field <req_field> (string)  # required",
              :req_bool_field => "--req_bool_field  # required",
            },
            :optional => {
              :opt_field => "[--opt_field] <opt_field> (string)  # optional",
            },
            :repeated => {
              :rep_field => "--rep_field[index] <rep_field> (uint32)  # array",
            }
          }
        }
      end

      it "should generate help for a command with nested field(s)" do
        args = ["nested_fields_help_test",
                "--help"]
        type, help = @subject.deserialize(args)
        type.should == :command_help
        help.should be_an_instance_of Hash

        nested_field_help = {
          :req_complex_field => {
            :description => "--req_complex_field  # required",
            :required => {
              :req_field=>".req_field <req_field> (string)  # required",
              :req_bool_field => ".req_bool_field  # required"
            },
            :optional => {
              :opt_field=>"[.opt_field] <opt_field> (string)  # optional",
            },
            :repeated => {
              :rep_field=>".rep_field[index] <rep_field> (uint32)  # array",
            }
          }
        }

        help.should == {
          :nested_fields_help_test => {
            :description => "Command to test generation of help for nested field.",
            :required => nested_field_help
          }
        }
      end

      it "should work for a specified field delimiter" do
        args = ["nested_fields_help_test",
                "--help"]
        type, help = @subject.deserialize(args, ":")
        type.should == :command_help
        help.should be_an_instance_of Hash

        nested_field_help = {
          :req_complex_field => {
            :description => "--req_complex_field  # required",
            :required => {
              :req_field=>":req_field <req_field> (string)  # required",
              :req_bool_field => ":req_bool_field  # required"
            },
            :optional => {
              :opt_field=>"[:opt_field] <opt_field> (string)  # optional",
            },
            :repeated => {
              :rep_field=>":rep_field[index] <rep_field> (uint32)  # array",
            }
          }
        }

        help.should == {
          :nested_fields_help_test => {
            :description => "Command to test generation of help for nested field.",
            :required => nested_field_help
          }
        }
      end

      it "should generate descriptions for all commands" do
        @subject.command_descriptions.should == test_desc_map
      end

      it "should cache the generated class map of commands" do
        args = ["simple_test",
                "--field", "value"]
        type, request = @subject.deserialize(args)
        type.should == :simple_test
        request.should be_an_instance_of SimpleTest
        request.field.should == "value"

        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[1]", "value_1"]
        type, request = @subject.deserialize(args)
        type.should == :repeated_test
        request.should be_an_instance_of RepeatedTest
        request.field.size.should == 2
        request.field[0].should == "value_0"
        request.field[1].should == "value_1"
      end

      it "should cache the generated descriptions of commands" do
        hash_1 = @subject.command_descriptions
        hash_2 = @subject.command_descriptions
        hash_1.should == test_desc_map
        hash_2.should == test_desc_map
        hash_1.object_id.should == hash_2.object_id
      end
    end
  end

  describe "#serialize" do
    context "serialize valid protocol objects" do
      it "should serialize simple field" do
        pb_handle = SimpleTest.new
        pb_handle.field = "field"
        hash = @subject.serialize(pb_handle)
        hash.should == {
          "field" => "field",
        }
      end

      it "should serialize repeated field" do
        pb_handle = RepeatedTest.new
        pb_handle.field = ["value_0", "value_1"]
        hash = @subject.serialize(pb_handle)
        hash.should == {
          "field[0]" => "value_0",
          "field[1]" => "value_1",
        }
      end

      it "should serialize nested field" do
        pb_handle = NestedTest.new
        pb_handle.complex_field = SimpleTest.new
        pb_handle.complex_field.field = "field"
        hash = @subject.serialize(pb_handle)
        hash.should == {
          "complex_field.field" => "field",
        }
      end

      it "should serialize bool field" do
        pb_handle = BoolTest.new
        pb_handle.field = true
        hash = @subject.serialize(pb_handle)
        hash.should == {
          "field" => "true",
        }
      end

      it "should serialize enum field" do
        pb_handle = EnumTest.new
        pb_handle.field = EnumTest::Enum::A
        hash = @subject.serialize(pb_handle)
        hash.should == {
          "field" => "A",
        }
      end
    end

    context "reject invalid protocol objects" do
      it "should raise an error when non-protocol buffer object is passed" do
        expect {
          @subject.serialize(Object.new)
        }.to raise_error{ |error|
          error.should be_an_instance_of ArgumentError
          error.message.should == "Expected protocol buffer object to be of type: #{Warden::Protocol::BaseMessage}, but received: #{Object}."
        }
      end

      it "should raise an error when ambiguous constants are defined in the module defining the enum field" do
        pb_handle = BadEnumTest.new
        pb_handle.field = BadEnumTest::BadEnum::A

        expect {
          @subject.serialize(pb_handle)
        }.to raise_error{ |error|
          error.should be_an_instance_of Warden::CommandsManager::SerializationError
          error.message.should == "Cannot serialize enum field: field. Duplicate constants defined in module: #{BadEnumTest::BadEnum}."
        }
      end
    end
  end
end
