module Helpers
  module Repl
    class SimpleTest
      include Warden::Protocol::BaseMessage

      required :field, :string, 1
    end

    class RepeatedTest
      include Warden::Protocol::BaseMessage

      repeated :field, :string, 1
    end

    class NestedTest
      include Warden::Protocol::BaseMessage

      required :complex_field, SimpleTest, 1
    end

    class BoolTest
      include Warden::Protocol::BaseMessage

      required :field, :bool, 1
    end

    class MixedTest
      include Warden::Protocol::BaseMessage

      repeated :complex_field, SimpleTest, 1
      required :bool_field, :bool, 2
    end

    class EnumTest
      include Warden::Protocol::BaseMessage

      module Enum
        A = 1
        B = 2
      end

      required :field, Enum, 1
    end

    class BadEnumTest
      include Warden::Protocol::BaseMessage

      # this will test the case where an error is thrown during serialization if
      # two enum constants can't have the same value.
      module BadEnum
        A = 1
        B = 1
      end

      required :field, BadEnum, 1
    end

    class WrongTypeTest
      include Warden::Protocol::BaseMessage

      required :int_field, :uint32, 1
    end

    class SimpleFieldsHelpTest
      include Warden::Protocol::BaseMessage

      required :req_field, :string, 1
      repeated :rep_field, :uint32, 2
      optional :opt_field, :string, 3, :default => "default_value"
      required :req_bool_field, :bool, 4
    end

    class NestedFieldsHelpTest
      include Warden::Protocol::BaseMessage

      required :req_complex_field, SimpleFieldsHelpTest, 1
    end

    def self.test_klass_map
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

    def self.test_description_map
      {
        "simple_test" => "Simple test command.",
        "repeated_test" => "Repeated test command.",
        "nested_test" => "Nested test command.",
        "bool_test" => "Bool test command.",
        "mixed_test" => "Mixed test command.",
        "enum_test" => "Enum test command.",
        "bad_enum_test" => "Bad enum test command.",
        "wrong_type_test" => "Wrong type test command.",
        "simple_fields_help_test" => "Test generation of help for simple fields.",
        "nested_fields_help_test" => "Test generation of help for nested field.",
      }
    end
  end
end
