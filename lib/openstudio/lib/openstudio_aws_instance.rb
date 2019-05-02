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

class OpenStudioAwsInstance
  include Logging

  attr_reader :openstudio_instance_type
  attr_reader :data
  attr_reader :private_key_file_name
  attr_reader :private_ip_address
  attr_reader :group_uuid

  # param security_groups can be a single instance or an array
  def initialize(aws_session, openstudio_instance_type, key_pair_name, security_groups, group_uuid, private_key,
                 private_key_file_name, subnet_id, proxy = nil)
    @data = nil # stored information about the instance
    @aws = aws_session
    @openstudio_instance_type = openstudio_instance_type # :server, :worker
    @key_pair_name = key_pair_name
    @security_groups = security_groups
    @group_uuid = group_uuid.to_s
    @init_timestamp = Time.now # This is the timestamp and is typically just tracked for the server
    @private_key = private_key
    @private_key_file_name = private_key_file_name
    @proxy = proxy
    @subnet_id = subnet_id

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
      volume_type: 'standard'
      # encrypted: true
    }
    resp = @aws.create_volume(options).to_hash

    # get the instance information
    test_result = @aws.describe_volumes(volume_ids: [resp[:volume_id]])
    begin
      Timeout.timeout(600) do # 10 minutes
        while test_result.nil? || test_result.instance_state.name != 'available'
          # refresh the server instance information

          sleep 5
          test_result = @aws.describe_volumes(volume_ids: [resp[:volume_id]])
          logger.info '... waiting for EBS volume to be available ...'
        end
      end
    rescue TimeoutError
      raise "EBS volume was unable to be created due to timeout #{instance_id}"
    end

    # need to wait until it is available

    @aws.attach_volume(
      volume_id: resp[:volume_id],
      instance_id: instance_id,
      # required
      device: '/dev/sdm'
    )

    # Wait for the volume to attach

    # true?
  end

  def launch_instance(image_id, instance_type, user_data, user_id, options = {})
    # determine the instance type of the server
    instance = {
      image_id: image_id,
      key_name: @key_pair_name,
      security_group_ids: @security_groups,
      subnet_id: options[:subnet_id],
      user_data: Base64.encode64(user_data),
      instance_type: instance_type,
      min_count: 1,
      max_count: 1
    }

    if options[:availability_zone]
      # use the availability zone from the server
      # logger.info("user_data #{user_data.inspect}")
      instance[:placement] ||= {}
      instance[:placement][:availability_zone] = options[:availability_zone]
    end

    if options[:associate_public_ip_address]
      # You have to delete the security group and subnet_id from the instance hash and put into the network interface
      # otherwise you will get an error on launch with an InvalidParameterCombination error.
      instance[:network_interfaces] = [
        {
          subnet_id: instance.delete(:subnet_id),
          groups: instance.delete(:security_group_ids),
          device_index: 0,
          associate_public_ip_address: true
        }
      ]
    end

    # Documentation for run_instances is here: http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/EC2/Client.html#run_instances-instance_method
    result = @aws.run_instances(instance)

    # determine how many processors are suppose to be in this image (lookup for now?)
    processors = find_processors(instance_type)

    # create the tag structure
    aws_tags = [
      { key: 'Name', value: "OpenStudio-#{@openstudio_instance_type.capitalize}" },
      { key: 'GroupUUID', value: @group_uuid },
      { key: 'NumberOfProcessors', value: processors.to_s },
      { key: 'Purpose', value: "OpenStudio#{@openstudio_instance_type.capitalize}" },
      { key: 'UserID', value: user_id }
    ]

    # add in any manual tags
    options[:tags].each do |tag|
      t = tag.split('=')
      if t.size != 2
        logger.error "Tag '#{t}' not defined or does not have an equal sign"
        raise "Tag '#{t}' not defined or does not have an equal sign"
        next
      end
      if ['Name', 'GroupUUID', 'NumberOfProcessors', 'Purpose', 'UserID'].include? t[0]
        logger.error "Tag name '#{t[0]}' is a reserved tag"
        raise "Tag name '#{t[0]}' is a reserved tag"
        next
      end

      aws_tags << { key: t[0].strip, value: t[1].strip }
    end

    # only asked for 1 instance, so therefore it should be the first
    begin
      tries ||= 5
      aws_instance = result.data.instances.first
      @aws.create_tags(
        resources: [aws_instance.instance_id],
        tags: aws_tags
      )
    rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
      sleep 5
      retry unless (tries -= 1).zero?
    end

    # get the instance information
    test_result = @aws.describe_instance_status(instance_ids: [aws_instance.instance_id]).data.instance_statuses.first
    begin
      Timeout.timeout(600) do # 10 minutes
        while test_result.nil? || test_result.instance_state.name != 'running'
          # refresh the server instance information

          sleep 5
          test_result = @aws.describe_instance_status(instance_ids: [aws_instance.instance_id]).data.instance_statuses.first
          logger.info '... waiting for instance to be running ...'
        end
      end
    rescue TimeoutError
      raise "Instance was unable to launch due to timeout #{aws_instance.instance_id}"
    end

    if options[:ebs_volume_size]
      create_and_attach_volume(options[:ebs_volume_size], aws_instance.instance_id, aws_instance.placement.availability_zone)
    end

    # now grab information about the instance
    # TODO: check lengths on all of arrays
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
        timestamp: @init_timestamp.to_i,
        time_created: @init_timestamp.to_s,
        # private_key_path: "#{File.expand_path(@private_key_path)}"
        #:private_key => @private_key, # need to stop printing this out
        location: 'AWS',
        availability_zone: @data.availability_zone,
        server: {
          id: @data.id,
          ip: "http://#{@data.ip}",
          dns: @data.dns,
          procs: @data.procs,
          private_key_file_name: @private_key_file_name,
          private_ip_address: @private_ip_address
        }
      }
    else
      raise 'do not know how to convert :worker instance to_os_hash. Use the os_aws.to_worker_hash method'
    end

    logger.info("server info #{h}")

    h
  end

  def ip
    @data.ip
  end

  def hostname
    "http://#{@data.ip}"
  end

  def procs
    @data.procs
  end

  # Return the total number of processors that available to run simulations. Note that this method reduces
  # the number of processors on the server node by a prespecified number.
  # @param instance [string], AWS instance type string
  # @return [int], total number of available processors
  def find_processors(instance)
    lookup = {
      'm3.medium' => 1,
      'm3.large' => 2,
      'm3.xlarge' => 4,
      'm3.2xlarge' => 8,
      'c3.large' => 2,
      'c3.xlarge' => 4,
      'c3.2xlarge' => 8,
      'c3.4xlarge' => 16,
      'c3.8xlarge' => 32,
      'r3.large' => 2,
      'r3.xlarge' => 4,
      'r3.2xlarge' => 8,
      'r3.4xlarge' => 16,
      'r3.8xlarge' => 32,
      't1.micro' => 1,
      't2.micro' => 1,
      'm1.small' => 1,
      'm2.2xlarge' => 4,
      'm2.4xlarge' => 8,
      'i2.xlarge' => 4,
      'i2.2xlarge' => 8,
      'i2.4xlarge' => 16,
      'i2.8xlarge' => 32,
      'd2.xlarge' => 4,
      'd2.2xlarge' => 8,
      'd2.4xlarge' => 16,
      'd2.8xlarge' => 36,
      'hs1.8xlarge' => 16
    }

    processors = 1
    if lookup.key?(instance)
      processors = lookup[instance]
    end

    if @openstudio_instance_type == :server
      # take out 5 of the processors for known processors.
      # 1 for server/web
      # 1 for queue (redis)
      # 1 for mongodb
      # 1 for web-background
      # 1 for rserve
      processors = [processors - 5, 1].max
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
    ssh_options = {
      proxy: get_proxy,
      key_data: [@private_key]
    }
    ssh_options.delete_if { |_k, v| v.nil? }
    begin
      Net::SCP.start(@data.ip, @user, ssh_options) do |scp|
        scp.upload! local_path, remote_path
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      return if retries == 5

      retries += 1
      sleep 2
      retry
    rescue StandardError
      # Unknown upload error, retry
      return if retries == 5

      retries += 1
      sleep 2
      retry
    end
  end

  # Send a command through SSH Shell to an instance.
  # Need to pass the command as a string.
  def shell_command(command, load_env = true)
    logger.info("ssh_command #{command} with load environment #{load_env}")
    command = "source /etc/profile; source ~/.bash_profile; #{command}" if load_env
    ssh_options = {
      proxy: get_proxy,
      key_data: [@private_key]
    }
    ssh_options.delete_if { |_k, v| v.nil? }
    Net::SSH.start(@data.ip, @user, ssh_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec command.to_s do |ch, success|
          raise "could not execute #{command}" unless success

          # "on_data" is called when the process wr_ites something to stdout
          ch.on_data do |_c, data|
            # $stdout.print data
            logger.info(data.inspect.to_s)
          end
          # "on_extended_data" is called when the process writes something to s_tde_rr
          ch.on_extended_data do |_c, _type, data|
            # $stderr.print data
            logger.info(data.inspect.to_s)
          end
        end
      end
      ssh.loop
      channel.wait
    end
  rescue Net::SSH::HostKeyMismatch => e
    e.remember_host!
    logger.info('key mismatch, retry')
    sleep 2
    retry
  rescue SystemCallError, Net::SSH::ConnectionTimeout, Timeout::Error => e
    # port 22 might not be available immediately after the instance finishes launching
    sleep 2
    logger.info('SystemCallError, Waiting for SSH to become available')
    retry
  end

  def wait_command(command)
    flag = 0
    while flag == 0
      logger.info("wait_command #{command}")
      ssh_options = {
        proxy: get_proxy,
        key_data: [@private_key]
      }
      ssh_options.delete_if { |_k, v| v.nil? }
      Net::SSH.start(@data.ip, @user, ssh_options) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec command.to_s do |ch, success|
            raise "could not execute #{command}" unless success

            # "on_data" is called_ when the process writes something to stdout
            ch.on_data do |_c, data|
              logger.info(data.inspect.to_s)
              if data.chomp == 'true'
                logger.info("wait_command #{command} is true")
                flag = 1
              else
                sleep 1
              end
            end
            # "on_extended_data" is called when the process writes some_thi_ng to stderr
            ch.on_extended_data do |_c, _type, data|
              logger.info(data.inspect.to_s)
              if data == 'true'
                logger.info("wait_command #{command} is true")
                flag = 1
              else
                sleep 1
              end
            end
          end
        end
        channel.wait
        ssh.loop
      end
    end
  rescue Net::SSH::HostKeyMismatch => e
    e.remember_host!
    logger.info('key mismatch, retry')
    sleep 10
    retry
  rescue SystemCallError, Net::SSH::ConnectionTimeout, Timeout::Error => e
    # port 22 might not be available immediately after the instance finishes launching
    sleep 10
    logger.info('Timeout.  Perhaps there is a communication error to EC2?  Will try again in 10 seconds')
    retry
  end

  def download_file(remote_path, local_path)
    retries = 0
    ssh_options = {
      proxy: get_proxy,
      key_data: [@private_key]
    }
    ssh_options.delete_if { |_k, v| v.nil? }
    begin
      Net::SCP.start(@data.ip, @user, ssh_options) do |scp|
        scp.download! remote_path, local_path
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      return if retries == 5

      retries += 1
      sleep 2
      retry
    rescue StandardError
      return if retries == 5

      retries += 1
      sleep 2
      retry
    end
  end

  private

  # store some of the data into a custom struct.  The instance is the full description.  The remaining fields are
  # just easier accessors to the data in the raw request except for procs which is a custom request.
  def create_struct(instance, procs)
    instance_struct = Struct.new(:instance, :id, :ip, :dns, :procs, :availability_zone, :private_ip_address, :launch_time)
    s = instance_struct.new(
      instance,
      instance[:instance_id],
      instance[:public_ip_address],
      instance[:public_dns_name],
      procs,
      instance[:placement][:availability_zone],
      instance[:private_ip_address],
      instance[:launch_time]
    )

    # store some values into the member variables
    @ip_address = instance[:public_ip_address]
    @private_ip_address = instance[:private_ip_address]
    @instance_id = instance[:instance_id]

    s
  end
end
