module Helper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def field(field, &blk)
      describe field do
        let(:field) do
          subject.fields.values.detect { |f| f.name == field }
        end

        instance_eval(&blk)
      end
    end

    def it_should_be_required
      it "should be required" do
        subject.should be_valid
        subject.send("#{field.name}=", nil)
        subject.should_not be_valid
      end
    end

    def it_should_be_optional
      it "should be optional" do
        subject.should be_valid
        subject.send("#{field.name}=", nil)
        subject.should be_valid
      end
    end

    def it_should_default_to(default)
      it "should default to #{default}" do
        instance = subject.reload
        instance.send(field.name).should == default
      end
    end

    def it_should_be_typed_as_uint
      it "should not allow a signed integer" do
        subject.send("#{field.name}=", -1)
        subject.should_not be_valid
      end

      it "should allow zero" do
        subject.send("#{field.name}=", 0)
        subject.should be_valid
      end

      it "should allow integers larger than zero" do
        subject.send("#{field.name}=", 37)
        subject.should be_valid
      end
    end

    def it_should_be_typed_as_string
      it "should allow an empty string" do
        subject.send("#{field.name}=", "")
        subject.should be_valid
      end

      it "should allow a non-empty string" do
        subject.send("#{field.name}=", "non-empty")
        subject.should be_valid
      end
    end
  end
end
