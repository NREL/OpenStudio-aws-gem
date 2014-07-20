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

require_relative 'openstudio_aws_logger'

class OpenStudioAwsWrapper
  include Logging

  attr_reader :group_uuid
  attr_reader :security_group_name
  attr_reader :key_pair_name
  attr_reader :server
  attr_reader :workers
  attr_reader :proxy

  # todo: put this into a module
  VALID_OPTIONS = [
    :proxy, :credentials
  ]

  def initialize(options = {}, group_uuid = nil)
    @group_uuid = group_uuid || Time.now.to_i.to_s

    @security_group_name = nil
    @key_pair_name = nil
    @private_key = nil
    @server = nil
    @workers = []

    # store an instance variable with the proxy for passing to instances for use in scp/ssh
    @proxy = options[:proxy] ? options[:proxy] : nil

    # need to remove the prxoy information here
    @aws = Aws::EC2.new(options[:credentials])
  end

  def create_or_retrieve_security_group(sg_name = nil)
    tmp_name = sg_name || 'openstudio-server-sg-v1'
    group = @aws.describe_security_groups(filters: [{ name: 'group-name', values: [tmp_name] }])
    logger.info "Length of the security group is: #{group.data.security_groups.length}"
    if group.data.security_groups.length == 0
      logger.info 'server group not found --- will create a new one'
      @aws.create_security_group(group_name: tmp_name, description: "group dynamically created by #{__FILE__}")
      @aws.authorize_security_group_ingress(

              group_name: tmp_name,
              ip_permissions: [
                { ip_protocol: 'tcp', from_port: 1, to_port: 65535, ip_ranges: [cidr_ip: '0.0.0.0/0'] }
              ]

      )
      @aws.authorize_security_group_ingress(

              group_name: tmp_name,
              ip_permissions: [
                { ip_protocol: 'icmp', from_port: -1, to_port: -1, ip_ranges: [cidr_ip: '0.0.0.0/0']
                }
              ]

      )

      # reload group information
      group = @aws.describe_security_groups(filters: [{ name: 'group-name', values: [tmp_name] }])
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

    { availability_zone_info: map }
  end

  def describe_availability_zones_json
    describe_availability_zones.to_json
  end

  def describe_total_instances
    resp = @aws.describe_instance_status

    region = resp.instance_statuses.length > 0 ? resp.instance_statuses.first.availability_zone : 'no_instances'
    { total_instances: resp.instance_statuses.length, region: region }
  end

  def describe_total_instances_json
    describe_total_instances.to_json
  end

  # return all of the running instances, or filter by the group_uuid & instance type
  def describe_running_instances(group_uuid = nil, openstudio_instance_type = nil)
    resp = nil
    if group_uuid
      resp = @aws.describe_instances(

              filters: [
                { name: 'instance-state-code', values: [0.to_s, 16.to_s] }, # running or pending
                { name: 'tag-key', values: ['GroupUUID'] },
                { name: 'tag-value', values: [group_uuid.to_s] } # todo: how to check for the server versions
                #{:name => "tag-value", :values => [group_uuid.to_s, "OpenStudio#{@openstudio_instance_type.capitalize}"]}
               # {:name => "tag:key=value", :values => ["GroupUUID=#{group_uuid.to_s}"]}
              ]
      )
    else
      # todo: need to restrict this to only the current user
      resp = @aws.describe_instances
    end

    instance_data = nil
    if resp
      if resp.reservations.length > 0
        resp = resp.reservations.first
        if resp.instances
          instance_data = []
          resp.instances.each do |i|
            instance_data << i.to_hash
          end

        end
      else
        logger.info 'no running instances found'
      end
    end

    instance_data
  end

  def describe_amis(filter = nil, image_ids = [], owned_by_me = true)
    resp = nil

    # todo: test the filter.  i don't think that it is exposed in the AWS gem?
    if owned_by_me
      if filter
        resp = @aws.describe_images(owners: [:self], filter: filter).data
      else
        resp = @aws.describe_images(owners: [:self]).data
      end
    else
      if filter
        resp = @aws.describe_images(filter: filter).data
      else
        resp = @aws.describe_images(image_ids: image_ids).data
      end
    end

    resp = resp.to_hash

    # map the tags to hashes
    resp[:images].each do |image|
      image[:tags_hash] = {}
      image[:tags_hash][:tags] = []
      image[:tags].each do |tag|
        if tag[:value]
          image[:tags_hash][tag[:key].to_sym] = tag[:value]
        else
          image[:tags_hash][:tags] << tag[:key]
        end
      end
    end

    resp
  end

  def create_or_retrieve_key_pair(key_pair_name = nil, private_key_file = nil)
    tmp_name = key_pair_name || "os-key-pair-#{@group_uuid}"

    # the describe_key_pairs method will raise an expection if it can't find the keypair, so catch it
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

      if File.exists(private_key_file)
        @private_key = File.read(private_key_file, 'r')
      else
        # should we raise?
        logger.error "Could not find the private key file to load from #{private_key_file}"
      end
    end

    logger.info("create key pair: #{@key_pair_name}")
  end

  def save_private_key(filename)
    if @private_key
      File.open(filename, 'w') { |f| f << @private_key }
      File.chmod(0600, filename)
    else
      logger.error 'no private key found in which to persist'
    end
  end

  def launch_server(image_id, instance_type, options = {})
    defaults = { user_id: 'unknown_user' }
    options = defaults.merge(options)

    user_data = File.read(File.expand_path(File.dirname(__FILE__)) + '/server_script.sh')
    @server = OpenStudioAwsInstance.new(@aws, :server, @key_pair_name, @security_group_name, @group_uuid, @private_key, @proxy)

    fail 'image_id is nil' unless image_id
    fail 'instance type is nil' unless instance_type
    @server.launch_instance(image_id, instance_type, user_data, options[:user_id])
  end

  def launch_workers(image_id, instance_type, num, options = {})
    defaults = { user_id: 'unknown_user' }
    options = defaults.merge(options)

    user_data = File.read(File.expand_path(File.dirname(__FILE__)) + '/worker_script.sh.template')
    user_data.gsub!(/SERVER_IP/, @server.data.ip)
    user_data.gsub!(/SERVER_HOSTNAME/, 'master')
    user_data.gsub!(/SERVER_ALIAS/, '')
    logger.info("worker user_data #{user_data.inspect}")

    # thread the launching of the workers

    num.times do
      @workers << OpenStudioAwsInstance.new(@aws, :worker, @key_pair_name, @security_group_name, @group_uuid, @private_key, @proxy)
    end

    threads = []
    @workers.each do |worker|
      threads << Thread.new do
        worker.launch_instance(image_id, instance_type, user_data, options[:user_id])
      end
    end
    threads.each { |t| t.join }

    # todo: do we need to have a flag if the worker node is successful?
    # todo: do we need to check the current list of running workers?
  end

  # blocking method that waits for servers and workers to be fully configured (i.e. execution of user_data has
  # occured on all nodes)
  def configure_server_and_workers
    # todo: add a timeout here!
    logger.info('waiting for server user_data to complete')
    @server.wait_command(@server.data.ip, '[ -e /home/ubuntu/user_data_done ] && echo "true"')
    @logger.info('waiting for worker user_data to complete')
    @workers.each { |worker| worker.wait_command(worker.data.ip, '[ -e /home/ubuntu/user_data_done ] && echo "true"') }

    ips = "master|#{@server.data.ip}|#{@server.data.dns}|#{@server.data.procs}|ubuntu|ubuntu|true\n"
    @workers.each { |worker| ips << "worker|#{worker.data.ip}|#{worker.data.dns}|#{worker.data.procs}|ubuntu|ubuntu|true\n" }
    file = Tempfile.new('ip_addresses')
    file.write(ips)
    file.close
    @server.upload_file(@server.data.ip, file.path, 'ip_addresses')
    file.unlink
    logger.info("ips #{ips}")
    @server.shell_command(@server.data.ip, 'chmod 664 /home/ubuntu/ip_addresses')
    @server.shell_command(@server.data.ip, '~/setup-ssh-keys.sh')
    @server.shell_command(@server.data.ip, '~/setup-ssh-worker-nodes.sh ip_addresses')

    mongoid = File.read(File.expand_path(File.dirname(__FILE__)) + '/mongoid.yml.template')
    mongoid.gsub!(/SERVER_IP/, @server.data.ip)
    file = Tempfile.new('mongoid.yml')
    file.write(mongoid)
    file.close
    @server.upload_file(@server.data.ip, file.path, '/mnt/openstudio/rails-models/mongoid.yml')
    @workers.each { |worker| worker.upload_file(worker.data.ip, file.path, '/mnt/openstudio/rails-models/mongoid.yml') }
    file.unlink

    # Does this command crash it?
    @server.shell_command(@server.data.ip, 'chmod 664 /mnt/openstudio/rails-models/mongoid.yml')
    @workers.each { |worker| worker.shell_command(worker.data.ip, 'chmod 664 /mnt/openstudio/rails-models/mongoid.yml') }

    true
  end

  # method to query the amazon api to find the server (if it exists), based on the group id
  # if it is found, then it will set the @server member variable.
  # Note that the information around keys and security groups is pulled from the instance information.
  def find_server(group_uuid = nil)
    group_uuid = group_uuid || @group_uuid

    logger.info "finding the server for groupid of #{group_uuid}"
    fail 'no group uuid defined either in member variable or method argument' if group_uuid.nil?

    resp = describe_running_instances(group_uuid, :server)
    if resp
      fail "more than one server running with group uuid of #{group_uuid} found, expecting only one" if resp.size > 1
      resp = resp.first
      if !@server
        logger.info "Server found and loading data into object [instance id is #{resp[:instance_id]}]"
        @server = OpenStudioAwsInstance.new(@aws, :server, resp[:key_name], resp[:security_groups].first[:group_name], group_uuid, @private_key)
        @server.load_instance_data(resp)
      else
        logger.info "Server instance is already defined with instance #{resp[:instance_id]}"
      end
    else
      fail 'could not find a running server instance'
    end
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
      puts 'Creating version 1 of the AMI file'
      version1 = {}

      # now grab the good keys - they should be sorted newest to older... so go backwards
      amis[:openstudio_server].keys.reverse.each do |key|
        next if amis[:openstudio_server][key][:deprecate]

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
      puts "Pretty version 1: #{JSON.pretty_generate(version1)}"

      amis = version1
    elsif version == 2
      # don't need to transform anything right now
      puts "Pretty version 2: #{JSON.pretty_generate(amis)}"
    end

    amis
  end

  def to_os_worker_hash
    worker_hash = []
    @workers.each { |worker|
      worker_hash.push(
                           id: worker.data.id,
                           ip: "http://#{worker.data.ip}",
                           dns: worker.data.dns,
                           procs: worker.data.procs
                       )
    }

    out = { workers: worker_hash }
    logger.info out

    out
  end

  # take the base version and increment the patch until
  def get_next_version(base, list_of_svs)
    b = base.to_version

    # first go through the array and test that there isn't any other versions > that in the array
    list_of_svs.each do |v|
      b = v.to_version if v.to_version.satisfies("#{b.major}.#{b.minor}.*") && v.to_version.patch > b.patch
    end

    # get the max version in the list_of_svs
    while list_of_svs.include?(b.to_s)
      b.patch += 1
    end

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
        puts 'found nil version, incrementing from 0.0.1'
        sv = get_next_version('0.0.1', list_of_svs)
      end
      list_of_svs << sv

      amis[:openstudio_server][sv.to_sym] = {} unless amis[:openstudio_server][sv.to_sym]
      a = amis[:openstudio_server][sv.to_sym]

      # initialize ami hash
      a[:amis] = {} unless a[:amis]

      # fill in data (this will override data currently)
      a[:deprecate] = true if sv.to_version.satisfies('0.0.*')
      a[:openstudio_version] = ami[:tags_hash][:openstudio_version] if ami[:tags_hash][:openstudio_version]
      a[:openstudio_version_sha] = ami[:tags_hash][:openstudio_version_sha] if ami[:tags_hash][:openstudio_version_sha]
      a[:user_uuid] = ami[:tags_hash][:user_uuid] if ami[:tags_hash][:user_uuid]
      a[:deprecate] = ami[:tags_hash][:deprecate] if ami[:tags_hash][:deprecate]
      a[:created_on] = ami[:tags_hash][:created_on] if ami[:tags_hash][:created_on]
      a[:openstudio_server_version] = sv.to_s
      if ami[:tags_hash][:tested]
        a[:tested] = ami[:tags_hash][:tested].downcase == 'true'
      else
        a[:tested] = false
      end

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
    # puts "Current AMIs: #{JSON.pretty_generate(amis)}"

    # merge in the existing AMIs the existing amis into the 'unknown category, but don't flag them as 'deprecate'
    # puts "Existing AMIs: #{JSON.pretty_generate(existing)}"
    existing.keys.each do |ami_key|
      next if ami_key == 'default'.to_sym # ignore default

      # get next version
      next_version = get_next_version('0.0.1', list_of_svs)
      list_of_svs << next_version

      amis[:openstudio_server][next_version.to_sym] = {} unless amis[:openstudio_server][next_version.to_sym]
      a = amis[:openstudio_server][next_version.to_sym]
      a[:amis] = {} unless a[:amis]

      a[:openstudio_version] = ami_key
      a[:amis][:server] = existing[ami_key][:server]
      a[:amis][:worker] = existing[ami_key][:worker]
      a[:amis][:cc2worker] = existing[ami_key][:cc2worker]
      a[:openstudio_server_version] = next_version.to_s
    end

    # puts "After merge: #{JSON.pretty_generate(amis)}"
    # flip these around for openstudio server section
    amis[:openstudio_server].keys.each do |key|
      next if key.to_s.to_version.satisfies('0.0.*')

      a = amis[:openstudio_server][key]
      ov = a[:openstudio_version]

      amis[:openstudio][ov] = {} unless amis[:openstudio][ov]
      osv = key
      amis[:openstudio][ov][osv] = {} unless amis[:openstudio][ov][osv]
      amis[:openstudio][ov][osv][:amis] = {} unless amis[:openstudio][ov][osv][:amis]
      amis[:openstudio][ov][osv][:amis][:server] = a[:amis][:server]
      amis[:openstudio][ov][osv][:amis][:worker] = a[:amis][:worker]
      amis[:openstudio][ov][osv][:amis][:cc2worker] = a[:amis][:cc2worker]
    end

    # sort the openstudio server version
    amis[:openstudio_server] = Hash[amis[:openstudio_server].sort_by { |k, v| v[:openstudio_server_version].to_version }.reverse]

    # now sort the openstudio section & determine the defaults
    amis[:openstudio].keys.each do |key|
      amis[:openstudio][key] = Hash[amis[:openstudio][key].sort_by { |k, _| k.to_s.to_version }.reverse]
      amis[:openstudio][key][:default] = amis[:openstudio][key].keys[0]
    end
    amis[:openstudio] = Hash[amis[:openstudio].sort_by { |k, _| k.to_s.to_version }.reverse]

    # puts "After sort: #{JSON.pretty_generate(amis)}"

    amis
  end
end
