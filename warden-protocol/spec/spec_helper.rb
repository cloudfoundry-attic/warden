# coding: UTF-8

require "rspec"
require "rspec/autorun"
require "warden/protocol"

Dir["./spec/support/**/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.include(Helper)
end
