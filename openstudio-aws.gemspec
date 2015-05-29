lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'openstudio/aws/version'

Gem::Specification.new do |s|
  s.name = 'openstudio-aws'
  s.version = OpenStudio::Aws::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ['Nicholas Long']
  s.email = ['Nicholas.Long@nrel.gov']
  s.homepage = 'http://openstudio.nrel.gov'
  s.summary = 'Start AWS EC2 instances for running distributed OpenStudio-based analyses'
  s.description = 'Custom classes for configuring clusters for OpenStudio & EnergyPlus analyses'
  s.license = 'LGPL'

  s.required_ruby_version = '>= 1.9.1'
  s.required_rubygems_version = '>= 1.3.6'

  s.add_dependency 'net-scp', '~> 1.1'
  s.add_dependency 'aws-sdk-core', '~> 2.0'
  s.add_dependency 'semantic', '~> 1.3'
  s.add_dependency 'sshkey', '~> 1.6'

  s.add_development_dependency 'bundler', '~> 1.7'
  s.add_development_dependency 'rake', '~> 10.4'

  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]
end
