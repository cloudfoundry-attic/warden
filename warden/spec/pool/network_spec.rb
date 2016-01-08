# coding: UTF-8

require "spec_helper"
require "warden/pool/network"

describe Warden::Pool::Network do

  context "create" do

    it "should iterate over IPs" do
      pool = Warden::Pool::Network.new("127.0.0.0/29")
      expect(pool.acquire).to eq "127.0.0.0"
      expect(pool.acquire).to eq "127.0.0.4"
      expect(pool.acquire).to be_nil
    end

    it "should work with different netmasks" do
      pool = Warden::Pool::Network.new("127.0.0.0/32")
      expect(pool.size).to eq 0
      pool = Warden::Pool::Network.new("127.0.0.0/31")
      expect(pool.size).to eq 0
      pool = Warden::Pool::Network.new("127.0.0.0/30")
      expect(pool.size).to eq 1
      pool = Warden::Pool::Network.new("127.0.0.0/29")
      expect(pool.size).to eq 2
      pool = Warden::Pool::Network.new("127.0.0.0/28")
      expect(pool.size).to eq 4
    end

    it "should have a netmask" do
      pool = Warden::Pool::Network.new("127.0.0.0/32")
      expect(pool.pooled_netmask).to be_a(Warden::Network::Netmask)
    end

    it "should default to a proper release delay" do
      pool = Warden::Pool::Network.new("127.0.0.0/29")
      expect(pool.release_delay).to be >= 5
    end
  end

  context "release" do
    it "should ignore networks that don't belong to the pool" do
      pool = Warden::Pool::Network.new("127.0.0.0/29")
      pool.release(Warden::Network::Address.new("10.10.10.10"))
      expect(pool.size).to eq 2
    end
  end
end
