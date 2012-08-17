# coding: UTF-8

shared_examples "documented request" do
  it "should have a description" do
    described_class.description.size.should be > 0
  end
end
