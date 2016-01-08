# coding: UTF-8

require "spec_helper"

require "warden/repl/commands_manager"
require "warden/protocol"

describe Warden::Repl::CommandsManager::FlagElement do
  describe "#new" do
    it "should raise an error when the flag element string is malformed" do
      expect {
        described_class.new("%")
      }.to raise_error { |error|
        expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagElementError
        expect(error.message).to eq "Invalid flag element: '%'."
      }

      expect {
        described_class.new("0")
      }.to raise_error { |error|
        expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagElementError
        expect(error.message).to eq "Invalid flag element: '0'."
      }
    end
  end

  describe "#name, #index" do
    it "should parse the field name and index from a valid flag element string" do
      obj = described_class.new("field")
      expect(obj.name).to eq "field"
      expect(obj.index).to be_nil

      obj = described_class.new("field[0]")
      expect(obj.name).to eq "field"
      expect(obj.index).to eq 0
    end
  end

  describe "#to_s" do
    it "should return the string representation" do
      expect(described_class.new("field").to_s).to eq "field"
      expect(described_class.new("field[0]").to_s).to eq "field[0]"
    end
  end

  describe "#==" do
    it "should return false for nil" do
      expect((described_class.new("a[0]") == nil)).to be false
    end

    it "should return false for different class type" do
      expect((described_class.new("a[0]") == Object.new)).to be false
    end

    it "should return false if attributes are different" do
      condition = (described_class.new("a[0]") == described_class.new("b[1]"))
      expect(condition).to be false
    end

    it "should return true if attribtues are the same" do
      condition = (described_class.new("a[0]") == described_class.new("a[0]"))
      expect(condition).to be true
    end
  end
end

describe Warden::Repl::CommandsManager::Flag do
  describe "#new" do
    it "should raise an error when the flag string is malformed" do
      expect {
        described_class.new("blah")
      }.to raise_error{ |error|
        expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
        expect(error.message).to eq "Invalid flag: 'blah'."
      }
    end

    it "should raise an error when an element of the flag string is malformed" do
      expect {
        described_class.new("--blah[0].-$%.foo.bar")
      }.to raise_error { |error|
        expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
        msg = "In flag: '--blah[0].-$%.foo.bar', Invalid flag element: '-$%'."
        expect(error.message).to eq msg
      }
    end
  end

  describe "#each" do
    it "should allow iteration over flag elements" do
      elements = [Warden::Repl::CommandsManager::FlagElement.new("a[0]"),
                  Warden::Repl::CommandsManager::FlagElement.new("b")]
      obj = described_class.new("--#{elements[0].to_s}.#{elements[1].to_s}")

      expect(obj.respond_to?(:each)).to be true
      index = 0
      obj.each do |element|
        expect(element).to be_an_instance_of Warden::Repl::CommandsManager::FlagElement
        expect(element).to eq elements[index]
        index += 1
      end

      expect(obj.respond_to?(:each_with_index)).to be true
      obj.each_with_index do |element, index|
        expect(element).to be_an_instance_of Warden::Repl::CommandsManager::FlagElement
        expect(element).to eq elements[index]
      end
    end
  end
end

describe Warden::Repl::CommandsManager do
  include Helpers::Repl

  before :each do
    @subject = Object.new
    @subject.extend(described_class)
  end

  describe "#deserialize" do
    it "should allow global help flag" do
      expect(@subject.deserialize(["--help"])).to be_nil
      expect(@subject.deserialize(["help"])).to be_nil
    end

    context "parse valid fields" do
      before :each do
        @request = nil
        allow(Warden::Protocol::Message::Type).to receive(:generate_klass_map).
          with("Request").and_return(Helpers::Repl.test_klass_map)
      end

      after :each do
        expect { @request.encode }.to_not raise_error if @request
      end

      it "should parse simple field" do
        args = ["simple_test",
                "--field", "value"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::SimpleTest
        expect(@request.field).to eq "value"
      end

      it "should parse repeated field" do
        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[1]", "value_1"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::RepeatedTest
        expect(@request.field.size).to eq 2
        expect(@request.field[0]).to eq "value_0"
        expect(@request.field[1]).to eq "value_1"
      end

      it "should parse nested field" do
        args  = ["nested_test",
                 "--complex_field.field", "value"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::NestedTest
        expect(@request.complex_field.field).to eq "value"
      end

      it "should parse bool field" do
        args = ["bool_test",
                "--field"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::BoolTest
        expect(@request.field).to be true
      end

      it "should parse enum field" do
        args = ["enum_test",
                "--field", "A"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::EnumTest
        expect(@request.field).to eq Helpers::Repl::EnumTest::Enum::A
      end

      it "should parse mixed fields" do
        args = ["mixed_test",
               "--bool_field",
               "--complex_field[0].field", "value"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::MixedTest
        expect(@request.complex_field).to be_an_instance_of Array
        expect(@request.complex_field.size).to eq 1
        expect(@request.complex_field[0]).to be_an_instance_of Helpers::Repl::SimpleTest
        expect(@request.complex_field[0].field).to eq "value"
        expect(@request.bool_field).to eq true
      end

      it "should allow overwriting of simple field" do
        args = ["simple_test",
                "--field", "value",
                "--field", "overwrite"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::SimpleTest
        expect(@request.field).to eq "overwrite"
      end

      it "should allow overwriting of repeated field" do
        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[0]", "overwrite"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::RepeatedTest
        expect(@request.field.size).to eq 1
        expect(@request.field[0]).to eq "overwrite"
      end

      it "should allow overwriting of nested field" do
        args  = ["nested_test",
                 "--complex_field.field", "value",
                 "--complex_field.field", "overwrite"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::NestedTest
        expect(@request.complex_field).to be_an_instance_of Helpers::Repl::SimpleTest
        expect(@request.complex_field.field).to eq "overwrite"
      end

      it "should allow overwriting of bool field" do
        args  = ["bool_test",
                 "--field",
                 "--field"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::BoolTest
        expect(@request.field).to be true
      end

      it "should allow overwriting of enum field" do
        args = ["enum_test",
                "--field", "A",
                "--field", "B"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::EnumTest
        expect(@request.field).to eq Helpers::Repl::EnumTest::Enum::B
      end

      it "should work for a different field delimiter" do
        args = ["nested_test",
                "--complex_field:field", "value"]

        @request = @subject.deserialize(args, ":")

        expect(@request).to be_an_instance_of Helpers::Repl::NestedTest
        expect(@request.complex_field.field).to eq "value"
      end

      it "should not treat -- in the middle as a field" do
        args = ["simple_test",
                "--field", "ab --help"]

        @request = @subject.deserialize(args)

        expect(@request).to be_an_instance_of Helpers::Repl::SimpleTest
        expect(@request.field).to eq "ab --help"
      end
    end

    context "reject invalid commands and fields" do
      before :each do
        allow(Warden::Protocol::Message::Type).to receive(:generate_klass_map).
          with("Request").and_return(Helpers::Repl.test_klass_map)
      end

      it "should raise an error when command is bad" do
        args = ["absent_command"]

        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::CommandError
          expect(error.message).to eq "Command: 'absent_command' is non-existent."
        }
      end

      it "should raise an error when bad help field is specified" do
        args = ["simple_fields_help_test",
                "help"]

        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'help'."
        }
      end

      it "should raise an error when simple field is bad" do
        args = ["simple_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'field'."
        }

        args = ["simple_test",
                "--field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: '--field'."
        }

        args = ["simple_test",
                "--bad_field", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--bad_field', the field: 'bad_field' is invalid."
          expect(error.message).to eq msg
        }
      end

      it "should raise error when repeated field is bad" do
        args = ["repeated_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'field'."
        }

        args = ["repeated_test",
                "--field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--field', the field: 'field' is not indexed."
          expect(error.message).to eq msg
        }

        args = ["repeated_test",
                "--field[1]", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--field[1]', the field: 'field[1]' is not indexed"
          msg << " correctly."
          expect(error.message).to eq msg
        }

        args = ["repeated_test",
                "--field[bad_index]", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--field[bad_index]',"
          msg << " Invalid flag element: 'field[bad_index]'."
          expect(error.message).to eq msg
        }

        args = ["repeated_test",
                "--field[-1]", "value_0"]

        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--field[-1]', Invalid flag element: 'field[-1]'."
          expect(error.message).to eq msg
        }

        args = ["repeated_test",
                "--field[0]", "value_0",
                "--field[2]", "value_2"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--field[2]',"
          msg << " the field: 'field[2]' is not indexed correctly."
          expect(error.message).to eq msg
        }
      end

      it "should raise an error when nested field is bad" do
        args = ["nested_test",
                "complex_field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'complex_field'."
        }

        args = ["nested_test",
                "--complex_field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: '--complex_field'."
        }

        args = ["nested_test",
                "--complex_field.absent_field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--complex_field.absent_field',"
          msg << " the field: 'absent_field' is invalid."
          expect(error.message).to eq msg
        }

        args = ["nested_test",
                "--complex_field.field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: '--complex_field.field'."
        }
      end

      it "should raise an error when bool field is bad" do
        args = ["bool_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'field'."
        }

        args = ["bool_test",
                "--field", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'value'."
        }
      end

      it "should raise an error when enum field is bad" do
        args = ["enum_test",
                "field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: 'field'."
        }

        args = ["enum_test",
                "--field"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          expect(error.message).to eq "Invalid flag: '--field'."
        }

        args = ["enum_test",
                "--bad_field", "value"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::FlagError
          msg = "In flag: '--bad_field', the field: 'bad_field' is invalid."
          expect(error.message).to eq msg
        }
      end

      it "should raise an error when wrong type is passed" do
        args = ["wrong_type_test",
                "--int_field", "blah"]
        expect {
          @subject.deserialize(args)
        }.to raise_error { |error|
          expect(error).to be_an_instance_of Warden::Repl::CommandsManager::CommandError
          expect(error.message).to eq "invalid value for Integer(): \"blah\""
        }
      end
    end

    context "generate help" do

      before(:each) do
        allow(Warden::Protocol::Message::Type).to receive(:generate_klass_map).
          with("Request").and_return(Helpers::Repl.test_klass_map)
        allow(@subject).to receive(:command_descriptions).
          and_return(Helpers::Repl.test_description_map)
      end

      it "should generate help for a command with simple field(s)" do
        args = ["simple_fields_help_test",
                "--help"]

        help = @subject.deserialize(args)

        expect(help).to be_an_instance_of Hash
        expect(help).to eq({
          :simple_fields_help_test => {
            :description => "Test generation of help for simple fields.",
            :required => {
              :req_field => "--req_field <req_field> (string)  # required",
              :req_bool_field => "--req_bool_field  # required",
            },
            :optional => {
              :opt_field => "[--opt_field <opt_field> (string)]  # optional",
            },
            :repeated => {
              :rep_field => "--rep_field[index] <rep_field> (uint32)  # array",
            }
          }
        })
      end

      it "should generate help for a command with nested field(s)" do
        args = ["nested_fields_help_test",
                "--help"]

        help = @subject.deserialize(args)

        expect(help).to be_an_instance_of Hash

        nested_field_help = {
          :req_complex_field => {
            :description => "--req_complex_field  # required",
            :required => {
              :req_field=>".req_field <req_field> (string)  # required",
              :req_bool_field => ".req_bool_field  # required"
            },
            :optional => {
              :opt_field=>"[.opt_field <opt_field> (string)]  # optional",
            },
            :repeated => {
              :rep_field=>".rep_field[index] <rep_field> (uint32)  # array",
            }
          }
        }

        expect(help).to eq({
          :nested_fields_help_test => {
            :description => "Test generation of help for nested field.",
            :required => nested_field_help
          }
        })
      end

      it "should work for a specified field delimiter" do
        args = ["nested_fields_help_test",
                "--help"]
        help = @subject.deserialize(args, ":")

        expect(help).to be_an_instance_of Hash

        nested_field_help = {
          :req_complex_field => {
            :description => "--req_complex_field  # required",
            :required => {
              :req_field=>":req_field <req_field> (string)  # required",
              :req_bool_field => ":req_bool_field  # required"
            },
            :optional => {
              :opt_field=>"[:opt_field <opt_field> (string)]  # optional",
            },
            :repeated => {
              :rep_field=>":rep_field[index] <rep_field> (uint32)  # array",
            }
          }
        }

        expect(help).to eq({
          :nested_fields_help_test => {
            :description => "Test generation of help for nested field.",
            :required => nested_field_help
          }
        })
      end
    end
  end

  describe "#serialize" do
    context "serialize valid protocol objects" do
      it "should serialize simple field" do
        pb_handle = Helpers::Repl::SimpleTest.new
        pb_handle.field = "field"
        hash = @subject.serialize(pb_handle)
        expect(hash).to eq({
          "field" => "field",
        })
      end

      it "should serialize repeated field" do
        pb_handle = Helpers::Repl::RepeatedTest.new
        pb_handle.field = ["value_0", "value_1"]
        hash = @subject.serialize(pb_handle)
        expect(hash).to eq({
          "field[0]" => "value_0",
          "field[1]" => "value_1",
        })
      end

      it "should serialize nested field" do
        pb_handle = Helpers::Repl::NestedTest.new
        pb_handle.complex_field = Helpers::Repl::SimpleTest.new
        pb_handle.complex_field.field = "field"
        hash = @subject.serialize(pb_handle)
        expect(hash).to eq({
          "complex_field.field" => "field",
        })
      end

      it "should serialize bool field" do
        pb_handle = Helpers::Repl::BoolTest.new
        pb_handle.field = true
        hash = @subject.serialize(pb_handle)
        expect(hash).to eq({
          "field" => "true",
        })
      end

      it "should serialize enum field" do
        pb_handle = Helpers::Repl::EnumTest.new
        pb_handle.field = Helpers::Repl::EnumTest::Enum::A
        hash = @subject.serialize(pb_handle)
        expect(hash).to eq({
          "field" => "A",
        })
      end
    end

    context "reject invalid protocol objects" do
      it "should raise an error when ambiguous constants are defined in the module defining the enum field" do
        pb_handle = Helpers::Repl::BadEnumTest.new
        pb_handle.field = Helpers::Repl::BadEnumTest::BadEnum::A

        expect {
          @subject.serialize(pb_handle)
        }.to raise_error{ |error|
          err_type = Warden::Repl::CommandsManager::SerializationError
          expect(error).to be_an_instance_of err_type

          msg = "Cannot serialize enum field: field."
          msg << " Duplicate constants defined in module:"
          msg << " #{Helpers::Repl::BadEnumTest::BadEnum}."

          expect(error.message).to eq msg
        }
      end
    end
  end

  describe "#convert_to_spawn_command" do
    it "should work" do
      run_command = Warden::Protocol::RunRequest.new(:handle => "handle",
                                                     :script => "script")
      spawn_command = @subject.convert_to_spawn_command(run_command)
      run_command.__beefcake_fields__.each_pair do |key, field|
        target = spawn_command.send(field.name)
        source = run_command.send(field.name)

        expect(target).to eq source

        if target
          expect(target.object_id).to_not eq source.object_id
        else
          expect(source).to be_nil
        end
      end
    end
  end

  describe "#generate_stream_command" do
    it "should work" do
      spawn_request = Warden::Protocol::SpawnRequest.new(:handle => "handle",
                                                         :script => "script")
      spawn_response = Warden::Protocol::SpawnResponse.new(:job_id => 1)

      stream_command = @subject.generate_stream_command(spawn_request,
                                                        spawn_response)
      handle = stream_command.handle
      expect(handle).to eq spawn_request.handle
      expect(handle.object_id).to_not eq spawn_request.handle.object_id
      expect(stream_command.job_id).to eq spawn_response.job_id
    end
  end
end
