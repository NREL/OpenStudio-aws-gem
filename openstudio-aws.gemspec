lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require "openstudio/aws/version"

Gem::Specification.new do |s|
  s.name = "openstudio-aws"
  s.version = OpenStudio::Aws::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Nicholas Long"]
  s.email = ["Nicholas.Long@nrel.gov"]
  s.homepage = 'http://openstudio.nrel.gov'
  s.summary = "Start AWS EC2 instances for running distributed OpenStudio-based analyses"
  s.description = "Custom classes for configuring clusters for OpenStudio & EnergyPlus analyses"
  s.license = "LGPL"

  s.required_ruby_version = ">= 1.9.3" 
  s.required_rubygems_version = ">= 1.3.6"
  
  s.add_dependency("net-scp", "~> 1.1.2")
  #s.add_dependency("aws-sdk", "~> 1.30.1")

  s.files = Dir.glob("lib/**/*") + %w(README.md Rakefile)
  s.test_files = Dir.glob("spec/**/*")
  s.require_path = "lib"
end
