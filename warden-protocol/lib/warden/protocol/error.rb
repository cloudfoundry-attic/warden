# coding: UTF-8

require "warden/protocol/base"

module Warden
  module Protocol
    class ErrorResponse
      include Warden::Protocol::BaseMessage

      optional :message, :string, 2
      optional :data, :string, 4
      repeated :backtrace, :string, 3
    end
  end
end
