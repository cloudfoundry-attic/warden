# coding: UTF-8

require "spec_helper"
require "warden/pool/uid"

describe Warden::Pool::Uid do

  before(:each) do
    Warden::Pool::Uid.should_receive(:local_uids).and_return([1000, 1001, 1002])
  end

  context "create" do

    it "should fail when range overlaps with local UIDs" do
      pool = nil
      expect do
        pool = Warden::Pool::Uid.new(1000, 5)
      end.to raise_error
    end

    it "should work when range doesn't overlap" do
      pool = nil
      expect do
        pool = Warden::Pool::Uid.new(2000, 5)
      end.to_not raise_error

      # Check size
      pool.size.should == 5

      # Check first entry
      pool.acquire.should == 2000
    end
  end

  context "acquire" do

    it "should raise when no uid is available" do
      pool = Warden::Pool::Uid.new(2000, 5)

      expect do
        (pool.size + 1).times { pool.acquire }
      end.to raise_error Warden::Pool::Uid::NoUidAvailable
    end
  end

  context "release" do

    it "should ignore uids that don't belong to the pool" do
      pool = Warden::Pool::Uid.new(2000, 5)
      pool.release(3000)

      pool.size.should == 5
    end
  end
end
