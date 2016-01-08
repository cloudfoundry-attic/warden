# coding: UTF-8

require "spec_helper"

require "warden/container/features/quota"

require "warden/protocol"

describe Warden::Container::Features::Quota do
  subject(:instance) do
    Class.new do
      include Warden::Container::Features::Quota
    end.new
  end

  before do
    allow(instance.class).to receive(:container_depot_mount_point_path).and_return("/")
    allow(instance.class).to receive(:container_depot_block_size).and_return(4096)

    allow(instance).to receive(:uid).and_return(1001)

    @current_limits = {}
    @default_limits = {
      :block_soft => 0,
      :block_hard => 0,
      :inode_soft => 0,
      :inode_hard => 0,
    }

    allow(instance.class).to receive(:repquota) do |uid|
      {
        uid => {
          :quota => {
            :block => {
              :soft => @current_limits[:block_soft] || @default_limits[:block_soft],
              :hard => @current_limits[:block_hard] || @default_limits[:block_hard],
            },
            :inode => {
              :soft => @current_limits[:inode_soft] || @default_limits[:inode_soft],
              :hard => @current_limits[:inode_hard] || @default_limits[:inode_hard],
            },
          },
        },
      }
    end

    allow(instance).to receive(:setquota) do |_, limits|
      @current_limits = limits
    end
  end

  describe "#do_limit_disk" do
    let(:request) { Warden::Protocol::LimitDiskRequest.new }
    let(:response) { Warden::Protocol::LimitDiskResponse.new }

    describe "setting 'block_soft'" do
      before do
        allow(instance.class).to receive(:disk_quota_enabled).and_return(true)
      end

      after do
        instance.do_limit_disk(request, response)

        expect(response.byte_soft).to eq 4096
        expect(response.block_soft).to eq 1
      end

      %W(byte_soft).each do |byte_property|
        it "via '#{byte_property}'" do
          request.send(byte_property + "=", 4000)
        end
      end

      %W(block_soft).each do |block_property|
        byte_property = block_property.gsub("block", "byte")

        it "via '#{block_property}'" do
          request.send(block_property + "=", 1)
        end

        it "via '#{block_property}' has precedence over '#{byte_property}'" do
          request.send(byte_property + "=", 8000)
          request.send(block_property + "=", 1)
        end
      end

      it "isn't overwritten when not specified" do
        @current_limits[:block_soft] = 1
      end
    end

    describe "setting 'block_hard'" do
      before do
        allow(instance.class).to receive(:disk_quota_enabled).and_return(true)
      end

      after do
        instance.do_limit_disk(request, response)

        expect(response.byte_limit).to eq 4096
        expect(response.byte).to eq 4096
        expect(response.byte_hard).to eq 4096

        expect(response.block_limit).to eq 1
        expect(response.block).to eq 1
        expect(response.block_hard).to eq 1
      end

      %W(byte_limit byte byte_hard).each do |byte_property|
        it "via '#{byte_property}'" do
          request.send(byte_property + "=", 4000)
        end
      end

      %W(block_limit block block_hard).each do |block_property|
        byte_property = block_property.gsub("block", "byte")

        it "via '#{block_property}'" do
          request.send(block_property + "=", 1)
        end

        it "via '#{block_property}' has precedence over '#{byte_property}'" do
          request.send(byte_property + "=", 8000)
          request.send(block_property + "=", 1)
        end
      end

      it "isn't overwritten when not specified" do
        @current_limits[:block_hard] = 1
      end
    end

    describe "setting 'inode_soft'" do
      before do
        allow(instance.class).to receive(:disk_quota_enabled).and_return(true)
      end

      after do
        instance.do_limit_disk(request, response)

        expect(response.inode_soft).to eq 1024
      end

      %W(inode_soft).each do |inode_property|
        it "via '#{inode_property}'" do
          request.send(inode_property + "=", 1024)
        end
      end

      it "isn't overwritten when not specified" do
        @current_limits[:inode_soft] = 1024
      end
    end

    describe "setting 'inode_hard'" do
      before do
        allow(instance.class).to receive(:disk_quota_enabled).and_return(true)
      end

      after do
        instance.do_limit_disk(request, response)

        expect(response.inode_limit).to eq 1024
        expect(response.inode).to eq 1024
        expect(response.inode_hard).to eq 1024
      end

      %W(inode_limit inode inode_hard).each do |inode_property|
        it "via '#{inode_property}'" do
          request.send(inode_property + "=", 1024)
        end
      end

      it "isn't overwritten when not specified" do
        @current_limits[:inode_hard] = 1024
      end
    end

    describe "disabling disk quota" do
      before do
        allow(instance.class).to receive(:disk_quota_enabled).and_return(false)
      end

      after do
        instance.do_limit_disk(request, response)

        %W(byte_limit byte byte_hard byte_soft).each do |byte_property|
          block_property = byte_property.gsub("byte", "block")
          inode_property = byte_property.gsub("byte", "inode")

          expect(response.method(byte_property ).call).to be_nil
          expect(response.method(block_property).call).to be_nil
          expect(response.method(inode_property).call).to be_nil
        end
      end

      it "should not be able to set any properties" do
        %W(byte_limit byte byte_hard byte_soft).each do |byte_property|
          block_property = byte_property.gsub("byte", "block")
          inode_property = byte_property.gsub("byte", "inode")

          request.send(byte_property  + "=", 4096)
          request.send(block_property + "=", 1)
          request.send(inode_property + "=", 1024)
        end
        request.send("byte_soft" + "=", 4000)
      end
    end
  end
end
