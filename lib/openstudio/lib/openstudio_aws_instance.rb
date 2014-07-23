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

class OpenStudioAwsInstance
  include Logging

  attr_reader :openstudio_instance_type
  attr_reader :data
  attr_reader :private_key_file_name
  attr_reader :group_uuid

  def initialize(aws_session, openstudio_instance_type, key_pair_name, security_group_name, group_uuid, private_key, private_key_file_name, proxy = nil, options = {})
    @data = nil # stored information about the instance
    @aws = aws_session
    @openstudio_instance_type = openstudio_instance_type # :server, :worker
    @key_pair_name = key_pair_name
    @security_group_name = security_group_name
    @group_uuid = group_uuid.to_s
    @private_key = private_key
    @private_key_file_name = private_key_file_name
    @proxy = proxy

    # Important System information
    @host = nil
    @instance_id = nil
    @user = 'ubuntu'
  end

  def create_and_attach_volume(size, instance_id, availability_zone)
    options = {
        size: size,
        # required
        availability_zone: availability_zone,
        volume_type: "standard"
        #encrypted: true
    }
    resp = @aws.create_volume(options).to_hash

    # get the instance information
    test_result = @aws.describe_volumes(volume_ids: [resp[:volume_id]])
    puts test_result
    begin
      Timeout.timeout(600) {# 10 minutes
        while test_result.nil? || test_result.instance_state.name != 'available'
          # refresh the server instance information

          sleep 5
          test_result = @aws.describe_volumes(volume_ids: [resp[:volume_id]])
          logger.info '... waiting for EBS volume to be available ...'
        end
      }
    rescue TimeoutError
      raise "EBS volume was unable to be created due to timeout #{instance_id}"
    end

    # need to wait until it is available

    @aws.attach_volume(
        {
            volume_id: resp[:volume_id],
            instance_id: instance_id,
            # required
            device: "/dev/sdh"
        }
    )

    # Wait for the volume to attach

    # true?
  end

  def launch_instance(image_id, instance_type, user_data, user_id, ebs_volume_size=nil)
    # logger.info("user_data #{user_data.inspect}")
    instance = {
        image_id: image_id,
        key_name: @key_pair_name,
        security_groups: [@security_group_name],
        user_data: Base64.encode64(user_data),
        instance_type: instance_type,
        min_count: 1,
        max_count: 1
    }
    result = @aws.run_instances(instance)

    # determine how many processors are suppose to be in this image (lookup for now?)
    processors = find_processors(instance_type)

    # only asked for 1 instance, so therefore it should be the first
    aws_instance = result.data.instances.first
    @aws.create_tags(
        resources: [aws_instance.instance_id],
        tags: [
            {key: 'Name', value: "OpenStudio-#{@openstudio_instance_type.capitalize}"}, # todo: abstract out the server and version
            {key: 'GroupUUID', value: @group_uuid},
            {key: 'NumberOfProcessors', value: processors.to_s},
            {key: 'Purpose', value: "OpenStudio#{@openstudio_instance_type.capitalize}"},
            {key: 'UserID', value: user_id}
        ]
    )

    # get the instance information
    test_result = @aws.describe_instance_status(instance_ids: [aws_instance.instance_id]).data.instance_statuses.first
    begin
      Timeout.timeout(600) {# 10 minutes
        while test_result.nil? || test_result.instance_state.name != 'running'
          # refresh the server instance information

          sleep 5
          test_result = @aws.describe_instance_status(instance_ids: [aws_instance.instance_id]).data.instance_statuses.first
          logger.info '... waiting for instance to be running ...'
        end
      }
    rescue TimeoutError
      raise "Instance was unable to launch due to timeout #{aws_instance.instance_id}"
    end

    if ebs_volume_size
      create_and_attach_volume(ebs_volume_size, aws_instance.instance_id, aws_instance.placement.availability_zone)
    end

    # now grab information about the instance
    # todo: check lengths on all of arrays
    instance_data = @aws.describe_instances(instance_ids: [aws_instance.instance_id]).data.reservations.first.instances.first.to_hash
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
    h = ''
    if @openstudio_instance_type == :server
      h = {
          group_id: @group_uuid,
          timestamp: @group_uuid,
          time_created: Time.at(@group_uuid.to_i),
          #private_key_path: "#{File.expand_path(@private_key_path)}"
          #:private_key => @private_key, # need to stop printing this out
          location: 'AWS',
          server: {
              id: @data.id,
              ip: 'http://' + @data.ip,
              dns: @data.dns,
              procs: @data.procs,
              private_key_file_name: @private_key_file_name
          }
      }
    else
      fail 'do not know how to convert :worker instance to_os_hash. Use the os_aws.to_worker_hash method'
    end

    logger.info("server info #{h}")

    h
  end

  def find_processors(instance)
    lookup = {
        "m2.2xlarge" => 4,
        "m2.4xlarge" => 8,
        "m3.medium" => 1,
        "m3.large" => 2,
        "m3.xlarge" => 4,
        "m3.2xlarge" => 8,
        "c3.large" => 2,
        "c3.xlarge" => 2,
        "c3.2xlarge" => 4,
        "c3.4xlarge" => 8,
        "c3.8xlarge" => 16,
        "r3.large" => 2,
        "r3.xlarge" => 4,
        "r3.2xlarge" => 8,
        "r3.4xlarge" => 16,
        "r3.8xlarge" => 32,
        "t1.micro" => 1,
        "m1.small" => 1,
    }

    processors = 1
    if lookup.key?(instance)
      processors = lookup[instance]
    else
      # logger.warn "Could not find the number of processors for instance type of #{instance}" if logger
    end

    processors
  end

  def get_proxy
    proxy = nil
    if @proxy
      if @proxy[:username]
        proxy = Net::SSH::Proxy::HTTP.new(@proxy[:host], @proxy[:port], user: @proxy[:username], password: proxy[:password])
      else
        proxy = Net::SSH::Proxy::HTTP.new(@proxy[:host], @proxy[:port])
      end
    end

    proxy
  end

  def upload_file(local_path, remote_path)
    retries = 0
    begin
      Net::SCP.start(@data.ip, @user, proxy: get_proxy, key_data: [@private_key]) do |scp|
        scp.upload! local_path, remote_path
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      return if retries == 5
      retries += 1
      sleep 1
      retry
    rescue
      # Unknown upload error, retry
      return if retries == 5
      retries += 1
      sleep 1
      retry
    end
  end

  # Send a command through SSH Shell to an instance.
  # Need to pass  the command as a string.
  def shell_command(command)
    begin
      logger.info("ssh_command #{command}")
      Net::SSH.start(@data.ip, @user, proxy: get_proxy, key_data: [@private_key]) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec "#{command}" do |ch, success|
            fail "could not execute #{command}" unless success

            # "on_data" is called when the process writes something to stdout
            ch.on_data do |c, data|
              # $stdout.print data
              logger.info("#{data.inspect}")
            end

            # "on_extended_data" is called when the process writes something to stderr
            ch.on_extended_data do |c, type, data|
              # $stderr.print data
              logger.info("#{data.inspect}")
            end
          end
        end
      end
    rescue Net::SSH::HostKeyMismatch => e
      e.remember_host!
      logger.info('key mismatch, retry')
      sleep 1
      retry
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 1
      logger.info('SystemCallError, Waiting for SSH to become available')
      retry
    end
  end

  def wait_command(command)
    begin
      flag = 0
      while flag == 0
        logger.info("wait_command #{command}")
        Net::SSH.start(@data.ip, @user, proxy: get_proxy, key_data: [@private_key]) do |ssh|
          channel = ssh.open_channel do |ch|
            ch.exec "#{command}" do |ch, success|
              fail "could not execute #{command}" unless success

              # "on_data" is called when the process writes something to stdout
              ch.on_data do |c, data|
                logger.info("#{data.inspect}")
                if data.chomp == 'true'
                  logger.info("wait_command #{command} is true")
                  flag = 1
                else
                  sleep 10
                end
              end

              # "on_extended_data" is called when the process writes something to stderr
              ch.on_extended_data do |c, type, data|
                logger.info("#{data.inspect}")
                if data == 'true'
                  logger.info("wait_command #{command} is true")
                  flag = 1
                else
                  sleep 10
                end
              end
            end
          end
        end
      end
    rescue Net::SSH::HostKeyMismatch => e
      e.remember_host!
      logger.info('key mismatch, retry')
      sleep 10
      retry
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 10
      logger.info('Timeout.  Perhaps there is a communication error to EC2?  Will try again')
      retry
    end
  end

  def download_file(remote_path, local_path)
    retries = 0
    begin
      Net::SCP.start(@data.ip, @user, proxy: get_proxy, key_data: [@private_key]) do |scp|
        scp.download! remote_path, local_path
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      return if retries == 5
      retries += 1
      sleep 1
      retry
    rescue
      return if retries == 5
      retries += 1
      sleep 1
      retry
    end
  end

  private

  # store some of the data into a custom struct.  The instance is the full description.  The remaining fields are
  # just easier accessors to the data in the raw request except for procs which is a custom request.
  def create_struct(instance, procs)
    instance_struct = Struct.new(:instance, :id, :ip, :dns, :procs)
    s = instance_struct.new(instance, instance[:instance_id], instance[:public_ip_address], instance[:public_dns_name], procs)

    # store some values into the member variables
    @ip_address = instance[:public_ip_address]
    @instance_id = instance[:instance_id]

    s
  end
end
