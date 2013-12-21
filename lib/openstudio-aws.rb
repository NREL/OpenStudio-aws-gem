require 'json'
require 'net/scp'
require 'yaml'

# AWS SDK
begin
  puts `gem list`
  gem "aws-sdk", ">= 1.30.1"
  require 'aws-sdk'
rescue LoadError
  puts "Failed to AWS-SDK gem"
  puts "  gem install aws-sdk"
  exit
end

require 'openstudio/aws/version'
require 'openstudio/aws/aws'
require 'openstudio/aws/config'
require 'openstudio/aws/send_data'

