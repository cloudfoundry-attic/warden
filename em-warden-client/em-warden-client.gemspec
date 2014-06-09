require File.expand_path('../lib/em/warden/client/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["mpage"]
  gem.email         = ["mpage@vmware.com"]
  gem.description   = "EM/Fiber compatible client for Warden"
  gem.summary       = "Provides EventMachine compatible code for talking with Warden"
  gem.homepage      = "http://www.cloudfoundry.com"

  gem.files         = Dir.glob("**/*")
  gem.test_files    = Dir.glob("spec/**/*")
  gem.name          = "em-warden-client"
  gem.require_paths = ["lib"]
  gem.version       = EventMachine::Warden::Client::VERSION

  gem.add_dependency('eventmachine')
  gem.add_dependency('warden-protocol', '>= 0.0.9')

  # Only needed for backwards API compatibility.
  gem.add_dependency('warden-client')

  gem.add_development_dependency('rake')
  gem.add_development_dependency('rspec', "~> 2.11.0")
end
