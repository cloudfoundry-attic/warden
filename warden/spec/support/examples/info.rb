# coding: UTF-8

shared_examples "info" do
  attr_reader :handle

  before do
    @handle = client.create.handle
  end

  it "should respond to an info request" do
    response = client.info(:handle => handle)
    expect(response.state).to eq "active"
    expect(response.container_path).to_not be_nil
  end
end
