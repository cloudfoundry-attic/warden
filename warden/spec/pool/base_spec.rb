# coding: UTF-8

require "spec_helper"
require "warden/pool/base"

describe Warden::Pool::Base do

  context "create" do

    it "should use a block to populate" do
      pool = Warden::Pool::Base.new(5) { |i| i }
      pool.size.should == 5
    end

    it "should take a release delay" do
      pool = Warden::Pool::Base.new(1, :release_delay => 0.01) { |i| i }

      # Acquire and release
      entry = pool.acquire
      pool.release(entry)

      # It should not be possible to immediately acquire the entry again
      pool.acquire.should be_nil
      sleep 0.02
      pool.acquire.should_not be_nil
    end
  end

  context "acquire" do

    it "should return nil when empty" do
      pool = Warden::Pool::Base.new(0) { |i| i }
      pool.acquire.should == nil
    end

    it "should return entry when not empty" do
      pool = Warden::Pool::Base.new(1) { |i| i }
      pool.acquire.should == 0
    end
  end

  context "fetch" do

    it "should return nil when empty" do
      pool = Warden::Pool::Base.new(0) { |i| i }
      pool.fetch(0).should == nil
    end

    it "should return entry when it exists" do
      pool = Warden::Pool::Base.new(5) { |i| i }
      pool.fetch(1).should == 1
      pool.fetch(1).should == nil
    end

    it "should return nil when not available" do
      pool = Warden::Pool::Base.new(5) { |i| i }
      pool.fetch(10).should == nil
    end
  end

  context "release" do

    it "should make entry size again" do
      pool = Warden::Pool::Base.new(0) { |i| i }
      pool.size.should == 0
      pool.release(0)
      pool.size.should == 1
    end
  end
end
