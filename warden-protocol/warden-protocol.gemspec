# -*- encoding: utf-8 -*-
require File.expand_path('../lib/warden/protocol/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Pieter Noordhuis"]
  gem.email         = ["pcnoordhuis@gmail.com"]
  gem.description   = %q{Protocol specification for Warden}
  gem.summary       = %q{Protocol specification for Warden}
  gem.homepage      = ""

  gem.files         = Dir.glob("lib/**/*")
  gem.test_files    = Dir.glob("spec/**/*")
  gem.name          = "warden-protocol"
  gem.require_paths = ["lib"]
  gem.version       = Warden::Protocol::VERSION

  gem.add_dependency "beefcake", "~> 0.3.0"

  gem.add_development_dependency "rspec", "~> 2.11.0"
end
