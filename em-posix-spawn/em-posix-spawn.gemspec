# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "em/posix/spawn/version"

Gem::Specification.new do |s|
  s.name        = "em-posix-spawn"
  s.version     = EventMachine::POSIX::Spawn::VERSION

  s.authors     = ["Pieter Noordhuis"]
  s.email       = ["pcnoordhuis@gmail.com"]
  s.summary     = "EventMachine-aware POSIX::Spawn::Child"

  s.files         = Dir.glob("lib/**/*")
  s.test_files    = Dir.glob("test/**/*")
  s.require_paths = ["lib"]

  s.add_runtime_dependency "eventmachine"
  s.add_runtime_dependency "posix-spawn"
  s.add_development_dependency "rake"
  s.add_development_dependency "minitest"
end
