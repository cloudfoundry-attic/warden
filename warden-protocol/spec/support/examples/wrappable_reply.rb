shared_examples "wrappable reply" do
  let(:wrapped) { subject.wrap }

  it "should respond to #wrap" do
    wrapped.should be_a(Warden::Protocol::WrappedRep)

    type_const = described_class.name.split("::").last.gsub(/Rep$/, "")
    wrapped.type.should == Warden::Protocol::Type.const_get(type_const)
    wrapped.payload.to_s.should == subject.encode.to_s
  end

  it "should retain class when unwrapped" do
    wrapped.reply.should be_a(described_class)
  end

  it "should retain properties when unwrapped" do
    wrapped.reply.to_hash.should == subject.to_hash
  end
end
