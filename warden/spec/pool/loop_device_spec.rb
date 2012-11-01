# coding: UTF-8

require "spec_helper"
require "warden/pool/loop_device"

describe Warden::Pool::LoopDevice do

  before(:each) do
    Warden::Pool::LoopDevice.stub(:occupied?).and_return(false)
  end

  context "create" do

    it "should iterate over device num" do
      pool = Warden::Pool::LoopDevice.new(1, 3)
      pool.acquire.should == 1
      pool.acquire.should == 2
      pool.acquire.should == 3
      expect { pool.acquire }.to raise_error(Warden::Pool::LoopDevice::NoLoopDeviceAvailable)
    end
  end

  context "release" do

    it "should ignore loop_device num that don't belong to the pool" do
      pool = Warden::Pool::LoopDevice.new(1, 10)
      pool.release(20)

      pool.size.should == 10
    end

    it "should increase the pool size if relase a valid device num" do
      pool = Warden::Pool::LoopDevice.new(1, 10)
      n = pool.acquire
      pool.size.should == 9

      pool.release(n)
      pool.size.should == 10
    end
  end
end
