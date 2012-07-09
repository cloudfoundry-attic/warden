shared_examples "info" do
  attr_reader :handle

  before do
    @handle = client.create.handle
  end

  it "should respond to an info request" do
    response = client.info(:handle => handle)
    response.state.should == "active"
  end
end
