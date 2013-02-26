module Helpers
  module Repl
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
      # this will test the case where an error is thrown during serialization if
      # two enum constants can't have the same value.
      module BadEnum
        A = 1
        B = 1
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
        "Test generation of help for simple fields."
      end
    end

    class NestedFieldsHelpTest < Warden::Protocol::BaseRequest
      required :req_complex_field, SimpleFieldsHelpTest, 1

      def self.description
        "Test generation of help for nested field."
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
      klass_map = {}

      map = test_klass_map
      map.each_value do |value|
        key = value.name.gsub(/(Request|Response)$/, "")
        key = key.split("::").last
        key = key.gsub(/(.)([A-Z])/, "\\1_\\2").downcase

        klass_map[key] = value.description
      end

      klass_map
    end
  end
end
