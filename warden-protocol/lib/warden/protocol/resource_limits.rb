# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class ResourceLimits
      include Warden::Protocol::BaseMessage

      optional :as, :uint64, 1
      optional :core, :uint64, 2
      optional :cpu, :uint64, 3
      optional :data, :uint64, 4
      optional :fsize, :uint64, 5
      optional :locks, :uint64, 6
      optional :memlock, :uint64, 7
      optional :msgqueue, :uint64, 8
      optional :nice, :uint64, 9
      optional :nofile, :uint64, 10
      optional :nproc, :uint64, 11
      optional :rss, :uint64, 12
      optional :rtprio, :uint64, 13
      optional :sigpending, :uint64, 14
      optional :stack, :uint64, 15
    end
  end
end
