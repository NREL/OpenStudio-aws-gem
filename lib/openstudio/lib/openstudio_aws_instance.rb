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

require 'securerandom'
require_relative 'openstudio_aws_logger'
require_relative 'openstudio_aws_methods'


class OpenStudioAwsInstance
  include Logging
  include OpenStudioAwsMethods

  attr_reader :openstudio_instance_type
  attr_reader :data

  def initialize(aws_session, openstudio_instance_type, key_pair_name, security_group_name, group_uuid, private_key, proxy = nil, options = {})
    @data = nil # stored information about the instance
    @aws = aws_session
    @openstudio_instance_type = openstudio_instance_type # :server, :worker
    @key_pair_name = key_pair_name
    @security_group_name = security_group_name
    @group_uuid = group_uuid.to_s
    @private_key = private_key
    @proxy = proxy 
  end

  def launch_instance(image_id, instance_type, user_data, user_id)
    #logger.info("user_data #{user_data.inspect}")
    instance = {
        :image_id => image_id,
        :key_name => @key_pair_name,
        :security_groups => [@security_group_name],
        :user_data => Base64.encode64(user_data),
        :instance_type => instance_type,
        :min_count => 1,
        :max_count => 1
    }
    #logger.info instance.inspect
    result = @aws.run_instances(instance)

    # determine how many processors are suppose to be in this image (lookup for now?)
    processors = find_processors(instance_type)

    # only asked for 1 instance, so therefore it should be the first 
    aws_instance = result.data.instances.first
    @aws.create_tags(
        {
            :resources => [aws_instance.instance_id],
            :tags => [
                {:key => 'Name', :value => "OpenStudio-#{@openstudio_instance_type.capitalize}"}, # todo: abstract out the server and version
                {:key => 'GroupUUID', :value => @group_uuid},
                {:key => 'NumberOfProcessors', :value => processors.to_s},
                {:key => 'Purpose', :value => "OpenStudio#{@openstudio_instance_type.capitalize}"},
                {:key => 'UserID', :value => user_id}
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
    # todo: check lengths on all of arrays
    instance_data = @aws.describe_instances({:instance_ids => [aws_instance.instance_id]}).data.reservations.first.instances.first.to_hash
    logger.info "instance description is: #{instance_data}"

    @data = create_struct(instance_data, processors)
  end
  
  # if the server already exists, then load the data about the server into the object
  # instance_data is passed in and in the form of the instance data (as a hash) structured as the 
  # result of the amazon describe instance
  def load_instance_data(instance_data)
    @data = create_struct(instance_data, find_processors(instance_data[:instance_type]))     
  end

  # Format of the OS JSON that is used for the command line based script
  def to_os_hash
    h = ""
    if @openstudio_instance_type == :server
      h = {
          :timestamp => @group_uuid,
          #:private_key => @private_key, # need to stop printing this out
          :server => {
              :id => @data.id,
              :ip => 'http://' + @data.ip,
              :dns => @data.dns,
              :procs => @data.procs
          }
      }
    else
      raise "do not know how to convert :worker instance to_os_hash. Use the os_aws.to_worker_hash method"
    end
    

    logger.info("server info #{h}")

    h
  end
  
  private

  # store the data into a custom struct.  The instance is the full description.  The remaining fields are
  # just easier accessors to the data in the raw request except for procs which is a custom request.
  def create_struct(instance, procs)
    instance_struct = Struct.new(:instance, :id, :ip, :dns, :procs)
    return instance_struct.new(instance, instance[:instance_id], instance[:public_ip_address], instance[:public_dns_name], procs)
  end

end
