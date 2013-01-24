# coding: UTF-8

require "spec_helper"
require "warden/pool/port"

describe Warden::Pool::Port do
  context "create" do
    it "should fail when the result contains less than 1000 ports" do
      expect do
        pool = Warden::Pool::Port.new(1000, 500)
      end.to raise_error Warden::WardenError
    end

    it "should succeed when the result contains more than 1000 ports" do
      pool = Warden::Pool::Port.new(61001, 4000)

      # Check size
      pool.size.should == 4000

      # Check first entry
      pool.acquire.should == 61001
    end
  end

  context "acquire" do
    it "should raise when no port is available" do
      pool = Warden::Pool::Port.new(61001, 1000)

      expect do
        (pool.size + 1).times { pool.acquire }
      end.to raise_error Warden::Pool::Port::NoPortAvailable
    end
  end

  context "release" do
    it "should ignore ports that don't belong to the pool" do
      pool = Warden::Pool::Port.new(61001, 1000)

      expect do
        pool.release(32000)
      end.to_not change(pool, :size)
    end

    it "should release ports that belong to the pool" do
      pool = Warden::Pool::Port.new(61001, 1000)

      port = pool.acquire

      expect do
        pool.release(port)
      end.to change(pool, :size)
    end
  end
end
