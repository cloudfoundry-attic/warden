# coding: UTF-8

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

  context "release" do

    it "should ignore networks that don't belong to the pool" do
      pool = Warden::Pool::Network.new("127.0.0.0", 2)
      pool.release(Warden::Network::Address.new("10.10.10.10"))

      pool.size.should == 2
    end
  end
end
