# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "warden/client/version"

Gem::Specification.new do |s|
  s.name        = "warden-client"
  s.version     = Warden::Client::VERSION
  s.authors     = ["Pieter Noordhuis", "Matt Page"]
  s.email       = ["pcnoordhuis@gmail.com", "mpage@vmware.com"]
  s.homepage    = "http://www.cloudfoundry.org/"
  s.summary     = %q{Client driver for warden, the ephemeral container manager.}
  s.description = %q{Provides a blocking client for interacting with the Warden.}

  s.files         = Dir.glob("lib/**/*")
  s.test_files    = Dir.glob("spec/**/*")
  s.executables   = []
  s.require_paths = ["lib"]

  s.add_runtime_dependency "warden-protocol", "~> 0.1.0"
  s.add_development_dependency "rspec", "~> 2.11.0"
end
