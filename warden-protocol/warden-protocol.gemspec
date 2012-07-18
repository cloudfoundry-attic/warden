# -*- encoding: utf-8 -*-
require File.expand_path('../lib/warden/protocol/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Pieter Noordhuis"]
  gem.email         = ["pcnoordhuis@gmail.com"]
  gem.description   = %q{Protocol specification for Warden}
  gem.summary       = %q{Protocol specification for Warden}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "warden-protocol"
  gem.require_paths = ["lib"]
  gem.version       = Warden::Protocol::VERSION

  gem.add_dependency "beefcake"

  gem.add_development_dependency "rspec", "~> 2.11"
end
