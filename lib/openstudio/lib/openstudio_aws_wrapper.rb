######################################################################
#  Copyright (c) 2008-2015, Alliance for Sustainable Energy.
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

require_relative 'openstudio_aws_logger'

class OpenStudioAwsWrapper
  include Logging

  attr_reader :group_uuid
  attr_reader :key_pair_name
  attr_reader :server
  attr_reader :workers
  attr_reader :proxy
  attr_reader :worker_keys

  attr_accessor :private_key_file_name
  attr_accessor :security_groups

  VALID_OPTIONS = [:proxy, :credentials]

  def initialize(options = {}, group_uuid = nil)
    @group_uuid = group_uuid || (SecureRandom.uuid).delete('-')

    @security_groups = []
    @key_pair_name = nil
    @private_key_file_name = nil
    @region = options[:region] || 'unknown-region'

    # If the keys exist in the directory then load those, otherwise create new ones.
    work_dir = options[:save_directory] || '.'
    if File.exist?(File.join(work_dir, 'ec2_worker_key.pem')) && File.exist?(File.join(work_dir, 'ec2_worker_key.pub'))
      logger.info "Worker keys already exist, loading from #{work_dir}"
      load_worker_key(File.join(work_dir, 'ec2_worker_key.pem'))
    else
      logger.info 'Generating new worker keys'
      @worker_keys = SSHKey.generate
    end

    @private_key = nil # Private key data

    # List of instances
    @server = nil
    @workers = []

    # store an instance variable with the proxy for passing to instances for use in scp/ssh
    @proxy = options[:proxy] ? options[:proxy] : nil

    # need to remove the prxoy information here
    @aws = Aws::EC2::Client.new(options[:credentials])
  end

  def create_or_retrieve_default_security_group(tmp_name = 'openstudio-server-sg-v2.1')
    group = @aws.describe_security_groups(filters: [{ name: 'group-name', values: [tmp_name] }])
    logger.info "Length of the security group is: #{group.data.security_groups.length}"
    if group.data.security_groups.length == 0
      logger.info 'security group not found --- will create a new one'
      @aws.create_security_group(group_name: tmp_name, description: "group dynamically created by #{__FILE__}")
      @aws.authorize_security_group_ingress(
        group_name: tmp_name,
        ip_permissions: [
          { ip_protocol: 'tcp', from_port: 22, to_port: 22, ip_ranges: [cidr_ip: '0.0.0.0/0'] }, # Eventually make this only the user's IP address seen by the internet
          { ip_protocol: 'tcp', from_port: 80, to_port: 80, ip_ranges: [cidr_ip: '0.0.0.0/0'] },
          { ip_protocol: 'tcp', from_port: 443, to_port: 443, ip_ranges: [cidr_ip: '0.0.0.0/0'] },
          { ip_protocol: 'tcp', from_port: 0, to_port: 65535, user_id_group_pairs: [{ group_name: tmp_name }] }, # allow all machines in the security group talk to each other openly
          { ip_protocol: 'icmp', from_port: -1, to_port: -1, ip_ranges: [cidr_ip: '0.0.0.0/0'] }
        ]
      )

      # reload group information
      group = @aws.describe_security_groups(filters: [{ name: 'group-name', values: [tmp_name] }])
    else
      logger.info 'Found existing security group'
    end

    @security_groups = [group.data.security_groups.first.group_id]
    logger.info("server_group #{group.data.security_groups.first.group_name}:#{group.data.security_groups.first.group_id}")

    group.data.security_groups.first
  end

  def describe_availability_zones
    resp = @aws.describe_availability_zones
    map = []
    resp.data.availability_zones.each do |zn|
      map << zn.to_hash
    end

    { availability_zone_info: map }
  end

  def describe_availability_zones_json
    describe_availability_zones.to_json
  end

  def total_instances_count
    resp = @aws.describe_instance_status

    availability_zone = resp.instance_statuses.length > 0 ? resp.instance_statuses.first.availability_zone : 'no_instances'

    { total_instances: resp.instance_statuses.length, region: @region, availability_zone: availability_zone }
  end

  def describe_all_instances
    resp = @aws.describe_instance_status

    resp
  end

  # describe the instances by group id (this is the default method)
  def describe_instances
    resp = nil
    if group_uuid
      resp = @aws.describe_instances(
        filters: [
          # {name: 'instance-state-code', values: [0.to_s, 16.to_s]}, # running or pending -- any state
          { name: 'tag-key', values: ['GroupUUID'] },
          { name: 'tag-value', values: [group_uuid.to_s] }
        ]
      )
    else
      resp = @aws.describe_instances
    end

    # Any additional filters
    instance_data = nil
    if resp
      instance_data = []
      resp.reservations.each do |r|
        r.instances.each do |i|
          i_h = i.to_hash
          if i_h[:tags].any? { |h| (h[:key] == 'GroupUUID') && (h[:value] == group_uuid.to_s) }
            instance_data << i_h
          end
        end
      end
    end

    instance_data
  end

  # return all of the running instances, or filter by the group_uuid & instance type
  def describe_running_instances(group_uuid = nil, openstudio_instance_type = nil)
    resp = nil
    if group_uuid
      resp = @aws.describe_instances(
        filters: [
          { name: 'instance-state-code', values: [0.to_s, 16.to_s] }, # running or pending
          { name: 'tag-key', values: ['GroupUUID'] },
          { name: 'tag-value', values: [group_uuid.to_s] }
        ]
      )
    else
      resp = @aws.describe_instances
    end

    instance_data = nil
    if resp
      instance_data = []
      resp.reservations.each do |r|
        r.instances.each do |i|
          i_h = i.to_hash
          if group_uuid && openstudio_instance_type
            # {:key=>"Purpose", :value=>"OpenStudioWorker"}
            if i_h[:tags].any? { |h| (h[:key] == 'Purpose') && (h[:value] == "OpenStudio#{openstudio_instance_type.capitalize}") } &&
               i_h[:tags].any? { |h| (h[:key] == 'GroupUUID') && (h[:value] == group_uuid.to_s) }
              instance_data << i_h
            end
          elsif group_uuid
            if i_h[:tags].any? { |h| (h[:key] == 'GroupUUID') && (h[:value] == group_uuid.to_s) }
              instance_data << i_h
            end
          elsif openstudio_instance_type
            if i_h[:tags].any? { |h| (h[:key] == 'Purpose') && (h[:value] == "OpenStudio#{openstudio_instance_type.capitalize}") }
              instance_data << i_h
            end
          else
            instance_data << i_h
          end
        end
      end
    end

    instance_data
  end

  # Describe the list of AMIs adn return the hash.
  # @param [Array] image_ids: List of image ids to find. If empty, then will find all images.
  # @param [Boolean] owned_by_me: Find only the images owned by the current user?
  # @return [Hash]
  def describe_amis(image_ids = [], owned_by_me = true)
    resp = nil

    if owned_by_me
      resp = @aws.describe_images(owners: [:self]).data
    else
      resp = @aws.describe_images(image_ids: image_ids).data
    end

    resp = resp.to_hash

    # map the tags to hashes
    resp[:images].each do |image|
      image[:tags_hash] = {}
      image[:tags_hash][:tags] = []

      # If the image is being created then its tags may be empty
      if image[:tags]
        image[:tags].each do |tag|
          if tag[:value]
            image[:tags_hash][tag[:key].to_sym] = tag[:value]
          else
            image[:tags_hash][:tags] << tag[:key]
          end
        end
      end
    end

    resp
  end

  # Stop specific instances based on the instance_ids
  # @param [Array] ids: Array of ids to stop
  def stop_instances(ids)
    resp = @aws.stop_instances(
      instance_ids: ids,
      force: true
    )

    resp
  end

  def terminate_instances(ids)
    resp = nil
    begin
      resp = @aws.terminate_instances(
        instance_ids: ids
      )
    rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
      # Log that the instances couldn't be found?
      resp = { error: 'instances could not be found' }
    end

    resp
  end

  def create_or_retrieve_key_pair(key_pair_name = nil)
    tmp_name = key_pair_name || "os-key-pair-#{@group_uuid}"

    # the describe_key_pairs method will raise an expectation if it can't find the key pair, so catch it
    resp = nil
    begin
      resp = @aws.describe_key_pairs(key_names: [tmp_name]).data
      fail 'looks like there are 2 key pairs with the same name' if resp.key_pairs.size >= 2
    rescue
      logger.info "could not find key pair '#{tmp_name}'"
    end

    if resp.nil? || resp.key_pairs.size == 0
      # create the new key_pair
      # check if the key pair name exists
      # create a new key pair everytime
      keypair = @aws.create_key_pair(key_name: tmp_name)

      # save the private key to memory (which can later be persisted via the save_private_key method)
      @private_key = keypair.data.key_material
      @key_pair_name = keypair.data.key_name
    else
      logger.info "found existing keypair #{resp.key_pairs.first}"
      @key_pair_name = resp.key_pairs.first[:key_name]

      # This will not set the private key because it doesn't live on the remote system
    end

    logger.info("create key pair: #{@key_pair_name}")
  end

  # Delete the key pair from aws
  def delete_key_pair(key_pair_name = nil)
    tmp_name = key_pair_name || "os-key-pair-#{@group_uuid}"
    resp = nil
    begin
      logger.info "Trying to delete key pair #{tmp_name}"
      resp = @aws.delete_key_pair(key_name: tmp_name)
    rescue
      logger.info "could not delete the key pair '#{tmp_name}'"
    end

    resp
  end

  def load_private_key(filename)
    unless File.exist? filename
      # check if the file basename exists in your user directory
      filename = File.expand_path("~/.ssh/#{File.basename(filename)}")
      if File.exist? filename
        logger.info "Found key of same name in user's home ssh folder #{filename}"
        # using the key in your home directory
      else
        fail "Could not find private key #{filename}" unless File.exist? filename
      end
    end

    @private_key_file_name = File.expand_path filename
    @private_key = File.read(filename)
  end

  # Load the worker key for communicating between the server and worker instances on AWS. The public key
  # will be automatically created when loading the private key
  #
  # @param private_key_filename [String] Fully qualified path to the worker private key
  def load_worker_key(private_key_filename)
    logger.info "Loading worker keys from #{private_key_filename}"
    @worker_keys_filename = private_key_filename
    @worker_keys = SSHKey.new(File.read(@worker_keys_filename))
  end

  # Save the private key to disk
  def save_private_key(directory = '.', filename = 'ec2_server_key.pem')
    if @private_key
      @private_key_file_name = File.expand_path "#{directory}/#{filename}"
      logger.info "Saving server private key in #{@private_key_file_name}"
      File.open(@private_key_file_name, 'w') { |f| f << @private_key }
      logger.info 'Setting permissions of server private key to 0600'
      File.chmod(0600, @private_key_file_name)
    else
      fail "No private key found in which to persist with filename #{filename}"
    end
  end

  # save off the worker public/private keys that were created
  def save_worker_keys(directory = '.')
    @worker_keys_filename = "#{directory}/ec2_worker_key.pem"
    logger.info "Saving worker private key in #{@worker_keys_filename}"
    File.open(@worker_keys_filename, 'w') { |f| f << @worker_keys.private_key }
    logger.info 'Setting permissions of worker private key to 0600'
    File.chmod(0600, @worker_keys_filename)

    wk = "#{directory}/ec2_worker_key.pub"
    logger.info "Saving worker public key in #{wk}"
    File.open(wk, 'w') { |f| f << @worker_keys.public_key }
  end

  def launch_server(image_id, instance_type, launch_options = {})
    defaults = {
      user_id: 'unknown_user',
      tags: [],
      ebs_volume_size: nil
    }
    launch_options = defaults.merge(launch_options)

    # replace the server_script.sh.template with the keys to add
    user_data = File.read(File.expand_path(File.dirname(__FILE__)) + '/server_script.sh.template')
    user_data.gsub!(/SERVER_HOSTNAME/, 'openstudio.server')
    user_data.gsub!(/WORKER_PRIVATE_KEY_TEMPLATE/, worker_keys.private_key.gsub("\n", '\\n'))
    user_data.gsub!(/WORKER_PUBLIC_KEY_TEMPLATE/, worker_keys.ssh_public_key)

    @server = OpenStudioAwsInstance.new(@aws, :server, @key_pair_name, @security_groups, @group_uuid, @private_key,
                                        @private_key_file_name, @proxy)

    # TODO: create the EBS volumes instead of the ephemeral storage - needed especially for the m3 instances (SSD)

    fail 'image_id is nil' unless image_id
    fail 'instance type is nil' unless instance_type
    @server.launch_instance(image_id, instance_type, user_data, launch_options[:user_id], launch_options)
  end

  def launch_workers(image_id, instance_type, num, launch_options = {})
    defaults = {
      user_id: 'unknown_user',
      tags: [],
      ebs_volume_size: nil,
      availability_zone: @server.data.availability_zone
    }
    launch_options = defaults.merge(launch_options)

    user_data = File.read(File.expand_path(File.dirname(__FILE__)) + '/worker_script.sh.template')
    user_data.gsub!(/SERVER_IP/, @server.data.private_ip_address)
    user_data.gsub!(/SERVER_HOSTNAME/, 'openstudio.server')
    user_data.gsub!(/WORKER_PUBLIC_KEY_TEMPLATE/, worker_keys.ssh_public_key)
    logger.info("worker user_data #{user_data.inspect}")

    # thread the launching of the workers
    num.times do
      @workers << OpenStudioAwsInstance.new(@aws, :worker, @key_pair_name, @security_groups, @group_uuid,
                                            @private_key, @private_key_file_name, @proxy)
    end

    threads = []
    @workers.each do |worker|
      threads << Thread.new do
        # create the EBS volumes instead of the ephemeral storage - needed especially for the m3 instances (SSD)
        worker.launch_instance(image_id, instance_type, user_data, launch_options[:user_id], launch_options)
      end
    end
    threads.each(&:join)

    # TODO: do we need to have a flag if the worker node is successful?
    # TODO: do we need to check the current list of running workers?
  end

  # blocking method that waits for servers and workers to be fully configured (i.e. execution of user_data has
  # occured on all nodes). Ideally none of these methods would ever need to exist.
  #
  # @return [Boolean] Will return true unless an exception is raised
  def configure_server_and_workers
    logger.info('waiting for server user_data to complete')
    @server.wait_command('[ -e /home/ubuntu/user_data_done ] && echo "true"')
    logger.info('waiting for worker user_data to complete')
    @workers.each { |worker| worker.wait_command('[ -e /home/ubuntu/user_data_done ] && echo "true"') }

    ips = "master|#{@server.data.private_ip_address}|#{@server.data.dns}|#{@server.data.procs}|ubuntu|ubuntu|true\n"
    @workers.each { |worker| ips << "worker|#{worker.data.private_ip_address}|#{worker.data.dns}|#{worker.data.procs}|ubuntu|ubuntu|true\n" }
    file = Tempfile.new('ip_addresses')
    file.write(ips)
    file.close
    @server.upload_file(file.path, 'ip_addresses')
    file.unlink
    logger.info("ips #{ips}")
    @server.shell_command('chmod 664 /home/ubuntu/ip_addresses')

    mongoid = File.read(File.expand_path(File.dirname(__FILE__)) + '/mongoid.yml.template')
    mongoid.gsub!(/SERVER_IP/, @server.data.private_ip_address)
    file = Tempfile.new('mongoid.yml')
    file.write(mongoid)
    file.close
    @server.upload_file(file.path, '/mnt/openstudio/rails-models/mongoid.yml')
    @workers.each { |worker| worker.upload_file(file.path, '/mnt/openstudio/rails-models/mongoid.yml') }
    file.unlink

    @server.shell_command('chmod 664 /mnt/openstudio/rails-models/mongoid.yml')
    @workers.each { |worker| worker.shell_command('chmod 664 /mnt/openstudio/rails-models/mongoid.yml') }

    true
  end

  # method to query the amazon api to find the server (if it exists), based on the group id
  # if it is found, then it will set the @server instance variable. The security groups are assigned from the
  # server node information on AWS if the security groups have not been initialized yet.
  #
  # Note that the information around keys and security groups is pulled from the instance information.
  # @param server_data_hash [Hash] Server data
  # @option server_data_hash [String] :group_id Group ID of the analysis
  # @option server_data_hash [String] :server.private_key_file_name Name of the private key to communicate to the server
  def find_server(server_data_hash)
    @group_uuid = server_data_hash[:group_id] || @group_uuid
    load_private_key(server_data_hash[:server][:private_key_file_name])

    logger.info "Finding the server for GroupUUID of #{group_uuid}"
    fail 'no GroupUUID defined either in member variable or method argument' if @group_uuid.nil?

    # This should really just be a single call to describe running instances
    @server = nil
    resp = describe_running_instances(group_uuid, :server)
    if resp
      fail "more than one server running with group uuid of #{group_uuid} found, expecting only one" if resp.size > 1
      resp = resp.first
      if !@server
        if resp
          logger.info "Server found and loading data into object [instance id is #{resp[:instance_id]}]"

          sg = resp[:security_groups].map { |s| s[:group_id] }
          # Set the security groups of the object if these groups haven't been assigned yet.
          @security_groups = sg if @security_groups.empty?
          logger.info "The security groups in aws wrapper are #{@security_groups}"

          # set the key name from AWS if it isn't yet assigned
          logger.info 'Setting the keyname in the aws wrapper'
          @key_pair_name = resp[:key_name] unless @key_pair_name

          @server = OpenStudioAwsInstance.new(@aws, :server, @key_pair_name, sg, @group_uuid, @private_key, @private_key_file_name, @proxy)

          @server.load_instance_data(resp)
        end
      else
        logger.info "Server instance is already defined with instance #{resp[:instance_id]}"
      end
    else
      logger.info 'could not find a running server instance'
    end

    # Find the worker instances.
    if @workers.size == 0
      resp = describe_running_instances(group_uuid, :worker)
      if resp
        resp.each do |r|
          @workers << OpenStudioAwsInstance.new(@aws, :worker, r[:key_name], r[:security_groups].map { |s| s[:group_id] }, @group_uuid, @private_key, @private_key_file_name, @proxy)
          @workers.last.load_instance_data(r)
        end
      end
    else
      logger.info 'Worker nodes are already defined'
    end

    # set the private key from the hash
    load_private_key server_data_hash[:server][:private_key_file_name]
    load_worker_key server_data_hash[:server][:worker_private_key_file_name]

    # Really don't need to return anything because this sets the class instance variable
    @server
  end

  # method to hit the existing list of available amis and compare to the list of AMIs on Amazon and then generate the
  # new ami list
  def create_new_ami_json(version = 1)
    # get the list of existing amis from developer.nrel.gov
    existing_amis = OpenStudioAmis.new(1).list

    # list of available AMIs from AWS
    available_amis = describe_amis

    amis = transform_ami_lists(existing_amis, available_amis)

    if version == 1
      version1 = {}

      # now grab the good keys - they should be sorted newest to older... so go backwards
      amis[:openstudio_server].keys.reverse_each do |key|
        a = amis[:openstudio_server][key]
        # this will override any of the old ami/os version
        version1[a[:openstudio_version].to_sym] = a[:amis]
      end

      # create the default version. First sort, then grab the first hash's values
      version1.sort_by
      default_v = nil
      version1 = Hash[version1.sort_by { |k, _| k.to_s.to_version }.reverse]
      default_v = version1.keys[0]

      version1[:default] = version1[default_v]
      amis = version1
    elsif version == 2
      # don't need to transform anything right now, only flag which ones are stable version so that the uploaded ami JSON has the
      # stable server for OpenStudio PAT to use.
      stable = JSON.parse File.read(File.join(File.dirname(__FILE__), 'ami_stable_version.json')), symbolize_names: true

      # go through and tag the versions of the openstudio instances that are stable,
      stable[:openstudio].each do |k, v|
        if amis[:openstudio][k.to_s] && amis[:openstudio][k.to_s][v.to_sym]
          amis[:openstudio][k.to_s][:stable] = v
        end
      end

      # I'm not sure what the below code is trying to accomplish. Are we even using the default?
      k, v = stable[:openstudio].first
      if k && v
        if amis[:openstudio][k.to_s]
          amis[:openstudio][:default] = v
        end
      end

      # now go through and if the OpenStudio version does not have a stable key, then assign it the most recent
      # stable AMI. This allows for easy testing so a new version of OpenStudio can use an existing AMI.
      stable[:openstudio].each do |stable_openstudio, stable_server|
        amis[:openstudio].each do |k, v|
          next if k == :default

          if k.to_s.to_version > stable_openstudio.to_s.to_version && v[:stable].nil?
            amis[:openstudio][k.to_s][:stable] = stable_server.to_s
          end
        end
      end
    end

    amis
  end

  # save off the instance configuration and instance information into a JSON file for later use
  def to_os_hash
    h = @server.to_os_hash

    h[:server][:worker_private_key_file_name] = @worker_keys_filename
    h[:workers] = @workers.map do |worker|
      {
        id: worker.data.id,
        ip: "http://#{worker.data.ip}",
        dns: worker.data.dns,
        procs: worker.data.procs,
        private_key_file_name: worker.private_key_file_name,
        private_ip_address: worker.private_ip_address
      }
    end

    h
  end

  # take the base version and increment the patch until.
  # TODO: DEPRECATE
  def get_next_version(base, list_of_svs)
    b = base.to_version

    # first go through the array and test that there isn't any other versions > that in the array
    list_of_svs.each do |v|
      b = v.to_version if v.to_version.satisfies("#{b.major}.#{b.minor}.*") && v.to_version.patch > b.patch
    end

    # get the max version in the list_of_svs
    b.patch += 1 while list_of_svs.include?(b.to_s)

    # return the value back as a string
    b.to_s
  end

  protected

  # transform the available amis into an easier to read format
  def transform_ami_lists(existing, available)
    # initialize ami hash
    amis = { openstudio_server: {}, openstudio: {} }
    list_of_svs = []

    available[:images].each do |ami|
      sv = ami[:tags_hash][:openstudio_server_version]

      if sv.nil? || sv == ''
        logger.info 'found nil Server Version, ignoring'
        next
      end
      list_of_svs << sv

      amis[:openstudio_server][sv.to_sym] = {} unless amis[:openstudio_server][sv.to_sym]
      a = amis[:openstudio_server][sv.to_sym]

      # initialize ami hash
      a[:amis] = {} unless a[:amis]

      # fill in data (this will override data currently)
      a[:openstudio_version] = ami[:tags_hash][:openstudio_version] if ami[:tags_hash][:openstudio_version]
      a[:openstudio_version_sha] = ami[:tags_hash][:openstudio_version_sha] if ami[:tags_hash][:openstudio_version_sha]
      a[:user_uuid] = ami[:tags_hash][:user_uuid] if ami[:tags_hash][:user_uuid]
      a[:created_on] = ami[:tags_hash][:created_on] if ami[:tags_hash][:created_on]
      a[:openstudio_server_version] = sv.to_s
      if ami[:tags_hash][:tested]
        a[:tested] = ami[:tags_hash][:tested].downcase == 'true'
      else
        a[:tested] = false
      end

      if ami[:tags_hash][:openstudio_version].to_version >= '1.6.0'
        if ami[:name] =~ /Server/
          a[:amis][:server] = ami[:image_id]
        elsif ami[:name] =~ /Worker/
          a[:amis][:worker] = ami[:image_id]
        end
      elsif ami[:tags_hash][:openstudio_version].to_version >= '1.5.0'
        if ami[:name] =~ /Server/
          a[:amis][:server] = ami[:image_id]
        elsif ami[:name] =~ /Worker/
          a[:amis][:worker] = ami[:image_id]
          a[:amis][:cc2worker] = ami[:image_id]
        end
      else
        if ami[:name] =~ /Worker|Cluster/
          if ami[:virtualization_type] == 'paravirtual'
            a[:amis][:worker] = ami[:image_id]
          elsif ami[:virtualization_type] == 'hvm'
            a[:amis][:cc2worker] = ami[:image_id]
          else
            fail "unknown virtualization_type in #{ami[:name]}"
          end
        elsif ami[:name] =~ /Server/
          a[:amis][:server] = ami[:image_id]
        end
      end
    end

    # flip these around for openstudio server section
    amis[:openstudio_server].keys.each do |key|
      a = amis[:openstudio_server][key]
      ov = a[:openstudio_version]

      amis[:openstudio][ov] ||= {}
      osv = key
      amis[:openstudio][ov][osv] ||= {}
      amis[:openstudio][ov][osv][:amis] ||= {}
      amis[:openstudio][ov][osv][:amis][:server] = a[:amis][:server]
      amis[:openstudio][ov][osv][:amis][:worker] = a[:amis][:worker]
      amis[:openstudio][ov][osv][:amis][:cc2worker] = a[:amis][:cc2worker]
    end

    # sort the openstudio server version
    amis[:openstudio_server] = Hash[amis[:openstudio_server].sort_by { |_k, v| v[:openstudio_server_version].to_version }.reverse]

    # now sort the openstudio section & determine the defaults
    amis[:openstudio].keys.each do |key|
      amis[:openstudio][key] = Hash[amis[:openstudio][key].sort_by { |k, _| k.to_s.to_version }.reverse]
      amis[:openstudio][key][:default] = amis[:openstudio][key].keys[0]
    end
    amis[:openstudio] = Hash[amis[:openstudio].sort_by { |k, _| k.to_s.to_version }.reverse]

    amis
  end
end
