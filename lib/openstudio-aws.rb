require 'json'
require 'net/scp'
require 'net/http'
require 'net/ssh/proxy/http'
require 'yaml'
require 'logger'
require 'securerandom'
require 'semantic'
require 'semantic/core_ext'
require 'fileutils'
require 'sshkey'

# AWS SDK CORE
begin
  require 'aws-sdk-core'
rescue LoadError
  puts 'Failed to load AWS-SDK-CORE gem'
  puts '  try running: gem install aws-sdk-core'

  exit 1
end

require 'openstudio/core_ext/hash'
require 'openstudio/lib/openstudio_aws_logger'
require 'openstudio/aws/aws'
require 'openstudio/aws/config'
require 'openstudio/aws/version'
require 'openstudio/lib/openstudio_aws_instance'
require 'openstudio/lib/openstudio_aws_wrapper'
require 'openstudio/lib/ami_list'
