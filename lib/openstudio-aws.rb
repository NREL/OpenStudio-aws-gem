require 'json'
require 'net/scp'
require 'yaml'
require 'logger'

# AWS SDK CORE
begin
  puts `gem list`
  require 'aws-sdk-core'
rescue LoadError
  puts "Failed to load AWS-SDK-CORE gem"
  puts "  try running: gem install aws-sdk-core"
  exit
end

require 'openstudio/aws/version'
require 'openstudio/aws/aws'
require 'openstudio/aws/config'

