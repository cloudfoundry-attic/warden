# coding: UTF-8

require "spec_helper"

describe Warden::Protocol::ResourceLimits do
  subject do
    described_class.new
  end

  field :as do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :core do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :cpu do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :data do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :fsize do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :locks do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :memlock do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :msgqueue do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :nice do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :nofile do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :nproc do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :rss do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :rtprio do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :sigpending do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end

  field :stack do
    it_should_be_optional
    it_should_be_typed_as_uint64
  end
end
