# coding: UTF-8

require "spec_helper"
require "warden/pool/port"

describe Warden::Pool::Port do

  context "create" do

    it "should fail when the result contains less than 1000 ports" do
      Warden::Pool::Port.should_receive(:ip_local_port_range).and_return([32768, 64002])

      expect do
        pool = Warden::Pool::Port.new
      end.to raise_error Warden::WardenError
    end

    it "should succeed when the result contains more than 1000 ports" do
      Warden::Pool::Port.should_receive(:ip_local_port_range).and_return([32768, 61000])
      pool = Warden::Pool::Port.new

      # Check size
      start, stop = 61001, 65001
      pool.size.should == stop - start

      # Check first entry
      pool.acquire.should == start
    end
  end

  context "acquire" do

    it "should raise when no port is available" do
      Warden::Pool::Port.should_receive(:ip_local_port_range).and_return([32768, 61000])
      pool = Warden::Pool::Port.new

      expect do
        (pool.size + 1).times { pool.acquire }
      end.to raise_error Warden::Pool::Port::NoPortAvailable
    end
  end

  context "release" do

    it "should ignore ports that don't belong to the pool" do
      Warden::Pool::Port.should_receive(:ip_local_port_range).and_return([32768, 61000])
      pool = Warden::Pool::Port.new
      old_size = pool.size
      pool.release(32000)

      pool.size.should == old_size
    end
  end
end
