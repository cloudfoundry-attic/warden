# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol

    # The byte limits are used to compute block limits on the server side.

    class LimitDiskRequest < BaseRequest
      required :handle, :string, 1

      optional :block_limit, :uint32, 10 # Alias for `block_hard`
      optional :block,       :uint64, 11 # Alias for `block_hard`
      optional :block_soft,  :uint64, 12
      optional :block_hard,  :uint64, 13

      optional :inode_limit, :uint32, 20 # Alias for `inode_hard`
      optional :inode,       :uint64, 21 # Alias for `inode_hard`
      optional :inode_soft,  :uint64, 22
      optional :inode_hard,  :uint64, 23

      optional :byte_limit, :uint32, 30 # Alias for `byte_hard`
      optional :byte,       :uint64, 31 # Alias for `byte_hard`
      optional :byte_soft,  :uint64, 32
      optional :byte_hard,  :uint64, 33

      def self.description
        "set or get the disk limit for the container."
      end
    end

    class LimitDiskResponse < BaseResponse
      optional :block_limit, :uint32, 10 # Alias for `block_hard`
      optional :block,       :uint64, 11 # Alias for `block_hard`
      optional :block_soft,  :uint64, 12
      optional :block_hard,  :uint64, 13

      optional :inode_limit, :uint32, 20 # Alias for `inode_hard`
      optional :inode,       :uint64, 21 # Alias for `inode_hard`
      optional :inode_soft,  :uint64, 22
      optional :inode_hard,  :uint64, 23

      optional :byte_limit, :uint32, 30 # Alias for `byte_hard`
      optional :byte,       :uint64, 31 # Alias for `byte_hard`
      optional :byte_soft,  :uint64, 32
      optional :byte_hard,  :uint64, 33
    end
  end
end
