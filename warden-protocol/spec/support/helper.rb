# coding: UTF-8

module Helper
  def self.included(base)
    base.extend(ClassMethods)
  end

  # Compare strings in hashes regardless of their encoding
  def compare_without_encoding(a, b)
    (a.keys & b.keys).each do |key|
      if a[key].respond_to?(:encoding)
        expect(a[key]).to eq(b[key].force_encoding(a[key].encoding))
      else
        expect(a[key]).to eq(b[key])
      end
    end
  end

  module ClassMethods
    def field(field, &blk)
      describe field do
        let(:field) do
          subject.__beefcake_fields__.values.detect { |f| f.name == field }
        end

        instance_eval(&blk)
      end
    end

    def it_should_be_required
      it "should be required" do
        expect(subject).to be_valid
        subject.send("#{field.name}=", nil)
        expect(subject).to_not be_valid
      end
    end

    def it_should_be_optional
      it "should be optional" do
        expect(subject).to be_valid
        subject.send("#{field.name}=", nil)
        expect(subject).to be_valid
      end
    end

    def it_should_default_to(default)
      it "should default to #{default}" do
        instance = subject.reload
        expect(instance.send(field.name)).to eq(default)
      end
    end

    def it_should_be_typed_as_uint
      it "should not allow a signed integer" do
        subject.send("#{field.name}=", -1)
        expect(subject).to_not be_valid
      end

      it "should allow zero" do
        subject.send("#{field.name}=", 0)
        expect(subject).to be_valid
      end

      it "should allow integers larger than zero" do
        subject.send("#{field.name}=", 37)
        expect(subject).to be_valid
      end
    end

    def it_should_be_typed_as_uint32
      it_should_be_typed_as_uint

      it "should allow integer 2^32-1" do
        subject.send("#{field.name}=", 2**32-1)
        expect(subject).to be_valid
      end

      it "should not allow integer 2^32" do
        subject.send("#{field.name}=", 2**32)
        expect(subject).to_not be_valid
      end
    end

    def it_should_be_typed_as_uint64
      it_should_be_typed_as_uint

      it "should allow integer 2^64-1" do
        subject.send("#{field.name}=", 2**64-1)
        expect(subject).to be_valid
      end

      it "should not allow integer 2^64" do
        subject.send("#{field.name}=", 2**64)
        expect(subject).to_not be_valid
      end
    end

    def it_should_be_typed_as_string
      it "should allow an empty string" do
        subject.send("#{field.name}=", "")
        expect(subject).to be_valid
      end

      it "should allow a non-empty string" do
        subject.send("#{field.name}=", "non-empty")
        expect(subject).to be_valid
      end
    end

    def it_should_be_typed_as_boolean
      it "should allow false" do
        subject.send("#{field.name}=", false)
        expect(subject).to be_valid
      end

      it "should allow true" do
        subject.send("#{field.name}=", true)
        expect(subject).to be_valid
      end
    end
  end
end
