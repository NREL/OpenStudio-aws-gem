# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2019, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER, THE UNITED STATES
# GOVERNMENT, OR ANY CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require 'bundler'
Bundler.setup

require 'rake'
require 'rspec/core/rake_task'

# Always create spec reports
require 'ci/reporter/rake/rspec'

# Gem tasks
require 'bundler/gem_tasks'

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'openstudio-aws'

RSpec::Core::RakeTask.new('spec') do |spec|
  spec.rspec_opts = ['--format', 'progress', '--format', 'CI::Reporter::RSpec']
  spec.pattern = 'spec/**/*_spec.rb'
end

RSpec::Core::RakeTask.new('spec:api') do |spec|
  spec.rspec_opts = ['--format', 'progress', '--format', 'CI::Reporter::RSpec']
  spec.pattern = 'spec/**/*_spec_api.rb'
end

RSpec::Core::RakeTask.new('spec:no_auth') do |spec|
  spec.rspec_opts = ['--format', 'progress', '--format', 'CI::Reporter::RSpec']

  file_list = FileList['spec/**/*_spec.rb']
  file_list = file_list.exclude('spec/**/aws_wrapper_spec.rb')
  file_list = file_list.exclude('spec/**/aws_spec.rb')
  file_list = file_list.exclude('spec/**/config_spec.rb')

  spec.pattern = file_list
end

task 'spec' => 'ci:setup:rspec'
task 'spec:api' => 'ci:setup:rspec'
task 'spec:no_auth' => 'ci:setup:rspec'

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
  h = @aws.os_aws.create_new_ami_json(2)
  File.open(f, 'w') { |f| f << JSON.pretty_generate(h) }
  puts JSON.pretty_generate(h)
end

require 'rubocop/rake_task'
desc 'Run RuboCop on the lib directory'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['--no-color', '--out=rubocop-results.xml']
  task.formatters = ['RuboCop::Formatter::CheckstyleFormatter']
  task.requires = ['rubocop/formatter/checkstyle_formatter']
  # don't abort rake on failure
  task.fail_on_error = false
end
