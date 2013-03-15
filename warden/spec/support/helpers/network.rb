module Helpers
  module Network
    def self.next_class_c
      @class_c ||= Warden::Network::Address.new("172.28.0.0")

      rv = @class_c
      @class_c = @class_c + 256
      rv
    end

    def self.included(base)
      base.instance_eval do
        let(:next_class_c) { Helpers::Network.next_class_c }
      end
    end
  end
end
