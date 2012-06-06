require "spec_helper"
require "warden/pool/network"

describe Warden::Pool::Network do

  context "create" do

    it "should iterate over IPs" do
      pool = Warden::Pool::Network.new("127.0.0.0", 2)
      pool.acquire.should == "127.0.0.0"
      pool.acquire.should == "127.0.0.4"
      pool.acquire.should be_nil
    end

    it "should default to a proper release delay" do
      pool = Warden::Pool::Network.new("127.0.0.0", 2)
      pool.release_delay.should >= 5
    end
  end
end
