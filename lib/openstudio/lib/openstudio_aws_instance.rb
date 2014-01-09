# NOTE: Do not modify this file as it is copied over. Modify the source file and rerun rake import_files
######################################################################
#  Copyright (c) 2008-2014, Alliance for Sustainable Energy.  
#  All rights reserved.
#  
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#  
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#  
#  You should have received a copy of the GNU Lesser General Public
#  License along with this library; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
######################################################################

######################################################################
# == Synopsis
#
#   Uses the aws-sdk gem to communicate with AWS
#
# == Usage
#
#  ruby aws.rb access_key secret_key us-east-1 EC2 launch_server "{\"instance_type\":\"t1.micro\"}"
#
#  ARGV[0] - Access Key
#  ARGV[1] - Secret Key
#  ARGV[2] - Region
#  ARGV[3] - Service (e.g. "EC2" or "CloudWatch")
#  ARGV[4] - Command (e.g. "launch_server")
#  ARGV[5] - Optional json with parameters associated with command
#
######################################################################

require 'securerandom'
require_relative 'openstudio_aws_logger'
require_relative 'openstudio_aws_methods'

class OpenStudioAwsInstance
  include Logging
  include OpenStudioAwsMethods

  attr_reader :openstudio_instance_type

  def initialize(aws_session, openstudio_instance_type, key_pair_name, security_group_name, group_uuid, timestamp)
    @data = nil # stored information about the instance
    @aws = aws_session
    @openstudio_instance_type = openstudio_instance_type # :server, :worker
    @key_pair_name = key_pair_name
    @security_group_name = security_group_name
    @group_uuid = group_uuid
    @timestamp = timestamp
  end

  def to_os_json
    json = ""
    if @openstudio_instance_type == :server
      json = {
          :timestamp => @timestamp,
          #:private_key => @private_key, # need to stop printing this out
          :server => {
              :id => @data.id,
              :ip => 'http://' + @data.ip,
              :dns => @data.dns,
              :procs => @data.procs
          }
      }.to_json
    end

    logger.info("server info #{json}")

    json
  end

  def launch_instance(image_id, instance_type, user_data)
    logger.info("user_data #{user_data.inspect}")
    result = @aws.run_instances(
        {
            :image_id => image_id,
            :key_name => @key_pair_name,
            :security_groups => [@security_group_name],
            :user_data => Base64.encode64(user_data),
            :instance_type => instance_type,
            :min_count => 1,
            :max_count => 1
        }
    )

    # only asked for 1 instance, so therefore it should be the first 
    aws_instance = result.data.instances.first
    @aws.create_tags(
        {
            :resources => [aws_instance.instance_id],
            :tags => [
                {:key => 'Name', :value => "OpenStudio-Server V#{OPENSTUDIO_VERSION}"},
                {:key => 'GroupUUID', :value => @group_uuid}
            ]
        }
    )

    # get the instance information 
    test_result = @aws.describe_instance_status({:instance_ids => [aws_instance.instance_id]}).data.instance_statuses.first
    begin
      Timeout::timeout(600) {# 10 minutes
        while test_result.nil? || test_result.instance_state.name != "running"
          # refresh the server instance information

          sleep 5
          test_result = @aws.describe_instance_status({:instance_ids => [aws_instance.instance_id]}).data.instance_statuses.first
          logger.info "... waiting for instance to be running ..."
        end
      }
    rescue TimeoutError
      raise "Intance was unable to launch due to timeout #{aws_instance.instance_id}"
    end

    # now grab information about the instance
    system_description = @aws.describe_instances({:instance_ids => [aws_instance.instance_id]}).data.reservations.first.instances.first

    processors = find_processors(instance_type)
    @data = create_struct(system_description, processors)
  end
end
