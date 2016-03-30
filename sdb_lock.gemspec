# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sdb_lock/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["KAWACHI Takashi"]
  gem.email         = ["kawachi@p-lucky.net"]
  gem.description   = %q{Lock library using Amazon SimpleDB}
  gem.summary       = %q{Lock library using Amazon SimpleDB}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "sdb_lock"
  gem.require_paths = ["lib"]
  gem.version       = SdbLock::VERSION

  gem.add_dependency 'aws-sdk', '~> 2'

  gem.add_development_dependency 'rake', '~> 0.9.2.2'
  gem.add_development_dependency 'minitest'
end
