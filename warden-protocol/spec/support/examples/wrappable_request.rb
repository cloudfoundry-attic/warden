# coding: UTF-8

shared_examples "wrappable request" do
  let(:wrapped) { subject.wrap }

  it "should respond to #wrap" do
    wrapped.should be_a(Warden::Protocol::Message)

    type_const = described_class.name.split("::").last.gsub(/Request$/, "")
    wrapped.type.should == Warden::Protocol::Message::Type.const_get(type_const)
    wrapped.payload.to_s.should == subject.encode.to_s
  end

  it "should retain class when unwrapped" do
    wrapped.request.should be_a(described_class)
  end

  it "should retain properties when unwrapped" do
    compare_without_encoding(wrapped.request.to_hash, subject.to_hash)
  end

  it "should retain properties when encoded and decoded" do
    freshly_wrapped = Warden::Protocol::Message.decode(wrapped.encode.to_s)
    compare_without_encoding(freshly_wrapped.request.to_hash, subject.to_hash)
  end
end
