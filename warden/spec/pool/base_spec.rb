# coding: UTF-8

require "spec_helper"
require "warden/pool/base"

describe Warden::Pool::Base do

  context "create" do

    it "should use a block to populate" do
      pool = Warden::Pool::Base.new(5) { |i| i }
      expect(pool.size).to eq 5
    end

    it "should take a release delay" do
      pool = Warden::Pool::Base.new(1, :release_delay => 0.01) { |i| i }

      # Acquire and release
      entry = pool.acquire
      pool.release(entry)

      # It should not be possible to immediately acquire the entry again
      expect(pool.acquire).to be_nil
      expect { pool.acquire }.to eventually_not(be nil)
    end
  end

  context "acquire" do

    it "should return nil when empty" do
      pool = Warden::Pool::Base.new(0) { |i| i }
      expect(pool.acquire).to eq nil
    end

    it "should return entry when not empty" do
      pool = Warden::Pool::Base.new(1) { |i| i }
      expect(pool.acquire).to eq 0
    end
  end

  context "fetch" do

    it "should return nil when empty" do
      pool = Warden::Pool::Base.new(0) { |i| i }
      expect(pool.fetch(0)).to eq nil
    end

    it "should return entry when it exists" do
      pool = Warden::Pool::Base.new(5) { |i| i }
      expect(pool.fetch(1)).to eq 1
      expect(pool.fetch(1)).to eq nil
    end

    it "should return nil when not available" do
      pool = Warden::Pool::Base.new(5) { |i| i }
      expect(pool.fetch(10)).to eq nil
    end
  end

  context "release" do

    it "should make entry size again" do
      pool = Warden::Pool::Base.new(0) { |i| i }
      expect(pool.size).to eq 0
      pool.release(0)
      expect(pool.size).to eq 1
    end
  end
end
