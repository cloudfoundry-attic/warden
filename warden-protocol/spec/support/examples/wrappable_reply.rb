# coding: UTF-8

shared_examples "wrappable response" do
  let(:wrapped) { subject.wrap }

  it "should respond to #wrap" do
    expect(wrapped).to be_a(Warden::Protocol::Message)

    type_const = described_class.name.split("::").last.gsub(/Response$/, "")
    expect(wrapped.type).to eq(Warden::Protocol::Message::Type.const_get(type_const))
    expect(wrapped.payload.to_s).to eq(subject.encode.to_s)
  end

  it "should retain class when unwrapped" do
    expect(wrapped.response).to be_a(described_class)
  end

  it "should retain properties when unwrapped" do
    compare_without_encoding(wrapped.response.to_hash, subject.to_hash)
  end

  it "should retain properties when encoded and decoded" do
    freshly_wrapped = Warden::Protocol::Message.decode(wrapped.encode.to_s)
    compare_without_encoding(freshly_wrapped.response.to_hash, subject.to_hash)
  end
end
