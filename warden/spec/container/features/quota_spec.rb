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
    instance.class.stub(:container_depot_mount_point_path).and_return("/")
    instance.class.stub(:container_depot_block_size).and_return(4096)

    instance.stub(:uid).and_return(1001)

    instance.stub(:setquota) do |uid, limits|
      # repquota returns what setquota sets
      instance.class.stub(:repquota).with(uid) do
        {
          uid => {
            :quota => {
              :block => {
                :soft => limits[:block_soft] || 0,
                :hard => limits[:block_hard] || 0,
              },
              :inode => {
                :soft => limits[:inode_soft] || 0,
                :hard => limits[:inode_hard] || 0,
              },
            }
          }
        }
      end
    end
  end

  describe "#do_limit_disk" do
    let(:request) { Warden::Protocol::LimitDiskRequest.new }
    let(:response) { Warden::Protocol::LimitDiskResponse.new }

    describe "setting 'block_soft'" do
      after do
        instance.do_limit_disk(request, response)

        response.byte_soft.should  == 4096
        response.block_soft.should == 1
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
    end

    describe "setting 'block_hard'" do
      after do
        instance.do_limit_disk(request, response)

        response.byte_limit.should == 4096
        response.byte.should       == 4096
        response.byte_hard.should  == 4096

        response.block_limit.should == 1
        response.block.should       == 1
        response.block_hard.should  == 1
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
    end

    describe "setting 'inode_soft'" do
      after do
        instance.do_limit_disk(request, response)

        response.inode_soft.should == 1024
      end

      %W(inode_soft).each do |inode_property|
        it "via '#{inode_property}'" do
          request.send(inode_property + "=", 1024)
        end
      end
    end

    describe "setting 'inode_hard'" do
      after do
        instance.do_limit_disk(request, response)

        response.inode_limit.should == 1024
        response.inode.should       == 1024
        response.inode_hard.should  == 1024
      end

      %W(inode_limit inode inode_hard).each do |inode_property|
        it "via '#{inode_property}'" do
          request.send(inode_property + "=", 1024)
        end
      end
    end
  end
end
