require 'bundler'
Bundler.setup

require 'rake'
require 'rspec/core/rake_task'

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'openstudio-aws'

task gem: :build
task :build do
  system 'gem build openstudio-aws.gemspec'
end

desc 'build and install gem locally'
task install: :build do
  system "gem install openstudio-aws-#{OpenStudio::Aws::VERSION}.gem --no-ri --no-rdoc"
end

desc 'build and release the gem using rubygems and git tags'
task release: :build do
  system "git tag -a v#{OpenStudio::Aws::VERSION} -m 'Tagging #{OpenStudio::Aws::VERSION}'"
  system 'git push --tags'
  system "gem push openstudio-aws-#{OpenStudio::Aws::VERSION}.gem"
  system "rm openstudio-aws-#{OpenStudio::Aws::VERSION}.gem"
end

RSpec::Core::RakeTask.new('spec') do |spec|
  spec.rspec_opts = %w(--format progress --format CI::Reporter::RSpec)
  spec.pattern = 'spec/**/*_spec.rb'
end

RSpec::Core::RakeTask.new('spec:api') do |spec|
  spec.rspec_opts = %w(--format progress --format CI::Reporter::RSpec)
  spec.pattern = 'spec/**/*_spec_api.rb'
end

RSpec::Core::RakeTask.new('spec:no_auth') do |spec|
  spec.rspec_opts = %w(--format progress --format CI::Reporter::RSpec)

  file_list = FileList['spec/**/*_spec.rb']
  file_list = file_list.exclude('spec/**/aws_wrapper_spec.rb')

  spec.pattern = file_list
end

task default: :spec

desc 'list out the AMIs for OpenStudio'
task :list_amis do
  @aws = OpenStudio::Aws::Aws.new

  dest_root = 'build/server/api'
  f = "#{dest_root}/v1/amis.json"
  File.delete(f) if File.exist?(f)
  FileUtils.mkdir_p File.dirname(f) unless Dir.exist? File.dirname(f)
  File.open(f, 'w') { |f| f << JSON.pretty_generate(@aws.os_aws.create_new_ami_json(1)) }

  f = "#{dest_root}/v2/amis.json"
  File.delete(f) if File.exist?(f)
  FileUtils.mkdir_p File.dirname(f) unless Dir.exist? File.dirname(f)
  File.open(f, 'w') { |f| f << JSON.pretty_generate(@aws.os_aws.create_new_ami_json(2)) }
end

desc 'uninstall all openstudio-aws gems'
task :uninstall do
  system 'gem uninstall openstudio-aws -a'
end

desc 'reinstall the gem (uninstall, build, and reinstall'
task reinstall: [:uninstall, :install]

require 'rubocop/rake_task'
desc 'Run RuboCop on the lib directory'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['--no-color', '--out=rubocop-results.xml']
  task.formatters = ['RuboCop::Formatter::CheckstyleFormatter']
  task.requires = ['rubocop/formatter/checkstyle_formatter']
  # don't abort rake on failure
  task.fail_on_error = false
end
