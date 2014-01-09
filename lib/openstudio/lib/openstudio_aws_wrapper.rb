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

class OpenStudioAwsWrapper
  include Logging

  attr_reader :security_group_name
  attr_reader :key_pair_name
  attr_reader :server
  attr_reader :workers

  def initialize(credentials = nil, group_uuid = nil)
    @group_uuid = group_uuid || SecureRandom.uuid

    @security_group_name = nil
    @key_pair_name = nil
    @private_key = nil
    @timestamp = Time.now.to_i
    @server = nil
    @workers = []

    # If you already set the credentials in another script in memory, then you won't have to do it here, but
    # it won't hurt if you do
    Aws.config = credentials if credentials
    @aws = Aws::EC2.new
  end

  def create_or_retrieve_security_group(sg_name = nil)
    tmp_name = sg_name || 'openstudio-server-sg-v1'
    group = @aws.describe_security_groups({:filters => [{:name => 'group-name', :values => [tmp_name]}]})
    logger.info "Length of the security group is: #{group.data.security_groups.length}"
    if group.data.security_groups.length == 0
      logger.info "server group not found --- will create a new one"
      @aws.create_security_group({:group_name => tmp_name, :description => "group dynamically created by #{__FILE__}"})
      @aws.authorize_security_group_ingress(
          {
              :group_name => tmp_name,
              :ip_permissions => [
                  {:ip_protocol => 'tcp', :from_port => 1, :to_port => 65535, :ip_ranges => [:cidr_ip => "0.0.0.0/0"]}
              ]
          }
      )
      @aws.authorize_security_group_ingress(
          {
              :group_name => tmp_name,
              :ip_permissions => [
                  {:ip_protocol => 'icmp', :from_port => -1, :to_port => -1, :ip_ranges => [:cidr_ip => "0.0.0.0/0"]
                  }
              ]
          }
      )

      # reload group information
      group = @aws.describe_security_groups({:filters => [{:name => 'group-name', :values => [tmp_name]}]})
    end
    @security_group_name = group.data.security_groups.first.group_name
    logger.info("server_group #{group.data.security_groups.first.group_name}")
  end

  def describe_availability_zones
    resp = @aws.describe_availability_zones
    map = []
    resp.data.availability_zones.each do |zn|
      map << zn.to_hash
    end

    {:availability_zone_info => map}
  end

  def describe_availability_zones_json
    describe_availability_zones.to_json
  end

  def describe_total_instances
    resp = @aws.describe_instance_status

    region = resp.instance_statuses.length > 0 ? resp.instance_statuses.first.availability_zone : "no_instances"
    {:total_instances => resp.instance_statuses.length, :region => region}
  end

  def describe_total_instances_json
    describe_total_instances.to_json
  end

  def create_or_retrieve_key_pair
    tmp_name = "os-key-pair-#{@timestamp}"
    # create a new key pair everytime
    keypair = @aws.create_key_pair({:key_name => tmp_name})

    # save the private key to memory
    @private_key = keypair.data.key_material
    @key_pair_name = keypair.data.key_name
    logger.info("create key pair: #{@key_pair_name}")
  end

  def save_private_key(filename)
    if @private_key
      File.open(filename, 'w') { |f| f << @private_key }
    end
  end

  def launch_server(image_id, instance_type)
    user_data = File.read(File.expand_path(File.dirname(__FILE__))+'/server_script.sh')
    @server = OpenStudioAwsInstance.new(@aws, :server, @key_pair_name, @security_group_name, @group_uuid, @timestamp)
    @server.launch_instance(image_id, instance_type, user_data)
  end

  def launch_workers(image_id, instance_type, num, server_ip)
    user_data = File.read(File.expand_path(File.dirname(__FILE__))+'/worker_script.sh.template')
    user_data.gsub!(/SERVER_IP/, @server.ip)
    user_data.gsub!(/SERVER_HOSTNAME/, 'master')
    user_data.gsub!(/SERVER_ALIAS/, '')
    logger.info("worker user_data #{user_data.inspect}")

    threads = []
    num.times do
      @workers << OpenStudioAwsInstance.new(@aws, @key_pair_name, @security_group_name, @group_uuid, @timestamp)
      threads << Thread.new do
        @workers.last.launch_instance(image_id, instance_type, user_data)
      end
    end
    threads.each { |t| t.join }
    
    # todo: do we need to have a flag if the worker node is successful?
  end


end
