# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cygnus/version'

Gem::Specification.new do |spec|
  spec.name          = "cygnus"
  spec.version       = Cygnus::VERSION
  spec.authors       = ["Rahul Kumar"]
  spec.email         = ["sentinel1879@gmail.com"]
  spec.description   = %q{best code browser eva}
  spec.summary       = %q{the finest code browser with exactly what you need and no more}
  spec.homepage      = "https://github.com/rkumar/cygnus"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
