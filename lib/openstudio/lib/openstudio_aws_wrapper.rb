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

require_relative 'openstudio_aws_logger'

class OpenStudioAwsWrapper
  include Logging
  require 'net/http'

  attr_reader :group_uuid
  attr_reader :key_pair_name
  attr_reader :server
  attr_reader :workers
  attr_reader :proxy
  attr_reader :worker_keys

  attr_accessor :private_key_file_name
  attr_accessor :security_groups

  VALID_OPTIONS = [:proxy, :credentials].freeze

  def initialize(options = {}, group_uuid = nil)
    @group_uuid = group_uuid || SecureRandom.uuid.delete('-')

    @security_groups = []
    @key_pair_name = nil
    @private_key_file_name = nil
    @region = options[:region] || 'unknown-region'

    # If the keys exist in the directory then load those, otherwise create new ones.
    @work_dir = File.expand_path options[:save_directory]
    if File.exist?(File.join(@work_dir, 'ec2_worker_key.pem')) && File.exist?(File.join(@work_dir, 'ec2_worker_key.pub'))
      logger.info "Worker keys already exist, loading from #{@work_dir}"
      load_worker_key(File.join(@work_dir, 'ec2_worker_key.pem'))
    else
      logger.info 'Generating new worker keys'
      @worker_keys = SSHKey.generate
    end

    @private_key = nil # Private key data
    @public_subnet_id = nil # Subnet id if using VPC networking
    @private_subnet_id = nil # Subnet id if using VPC networking

    # List of instances
    @server = nil
    @workers = []

    # store an instance variable with the proxy for passing to instances for use in scp/ssh
    @proxy = options[:proxy] || nil

    # need to remove the prxoy information here
    @aws = Aws::EC2::Client.new(options[:credentials])
  end

  def create_or_retrieve_default_server_vpc(vpc_name = 'oss-vpc-v0.1')
    vpc = find_or_create_vpc(vpc_name)
    public_subnet = find_or_create_public_subnet(vpc)
    private_subnet = find_or_create_private_subnet(vpc)
    igw = find_or_create_igw(vpc)
    eigw = find_or_create_eigw(vpc)
    public_rtb = find_or_create_public_rtb(vpc, public_subnet)
    private_rtb = find_or_create_private_rtb(vpc, private_subnet)
  end

  def retrieve_visible_ip()
    Net::HTTP.get(URI('http://checkip.amazonaws.com')).strip
  end

  def retrieve_vpc(vpc_name)
    vpcs = @aws.describe_vpcs(filters: [
        {name: 'tag:Name', values: [vpc_name]}
    ])
    if vpcs.vpcs.length == 1
      vpcs.vpcs.first
    elsif vpcs.vpcs.length == 0
      false
    else
      raise "Did not find 1 VPC instance with name #{vpc_name}, instead found #{vpcs.vpcs.length}. Please delete these vpcs to allow for reconstruction."
    end
  end

  def reload_vpc(vpc)
    vpcs = @aws.describe_vpcs({vpc_ids: [vpc.vpc_id]}).vpcs
    if vpcs.length == 1
      vpcs.first
    else
      raise "Did not find #{vpc.vpc_id}"
    end
  end

  def retrieve_subnet(subnet_name, vpc)
    subnets = @aws.describe_subnets(filters: [
        {name: 'tag:Name', values: [subnet_name]},
        {name: 'vpc-id', values: [vpc.vpc_id]}
    ])
    if subnets.subnets.length == 1
      subnets.subnets.first
    elsif subnets.subnets.length == 0
      false
    else
      raise "Did not find 1 subnet instance with name #{subnet_name}, instead found #{subnets.subnets.length}. Please delete #{vpc.vpc_id} to allow the vpc to be reconstructed."
    end
  end

  def reload_subnet(subnet)
    subnets = @aws.describe_subnets({subnet_ids: [subnet.subnet_id]}).subnets
    if subnets.length == 1
      subnets.first
    else
      raise "Did not find #{subnet.subnet_id}"
    end
  end

  def retrieve_vpc_name(vpc)
    name_tags = vpc.tags.select { |tag| tag.key == 'Name' }
    name_tags.empty? ? raise("Unable to find tag with key 'Name' for #{vpc.vpc_id}") : name_tags.first.value
  end

  def retrieve_igw(vpc)
    igws = @aws.describe_internet_gateways({filters: [
        {name: "attachment.vpc-id", values: [vpc.vpc_id]}
    ]}).internet_gateways
    if igws.length == 1
      igws.first
    else igws.length == 0
      false
    end
  end

  def reload_igw(igw)
    igws = @aws.describe_internet_gateways({internet_gateway_ids: [igw.internet_gateway_id]}).internet_gateways
    if igws.length == 1
      igws.first
    else
      raise "Did not find #{igw.internet_gateway_id}"
    end
  end

  def retrieve_eigw(vpc)
    eigws = @aws.describe_egress_only_internet_gateways({max_results: 254}).egress_only_internet_gateways
    if eigws.length == 0
      false
    else
      eigw = eigws.select { |eigw| eigw.attachments[0].vpc_id == vpc.vpc_id }[0]
      eigw.nil? ? false : eigw
    end
  end

  def reload_eigw(eigw)
    eigws = @aws.describe_egress_only_internet_gateways({egress_only_internet_gateway_ids: [eigw.egress_only_internet_gateway_id]})
    if eigws.length == 1
      eigws.first
    else
      raise "Did not find #{eigw.egress_only_internet_gateway_id}"
    end
  end

  def retrieve_rtb(subnet)
    rtbs = @aws.describe_route_tables({}).route_tables
    rtbs = rtbs.select { |rtb| rtb.associations.map { |association| association.subnet_id }.include? subnet.subnet_id }
    if rtbs.length == 1
      rtbs.first
    elsif rtbs.length == 0
      false
    else
      # This should be impossible
      raise "Did not find 1 rtb for #{subnet.subnet_id}, instead found #{rtbs.length}"
    end
  end

  def reload_rtb(rtb)
    rtbs = @aws.describe_route_tables({route_table_ids: [rtb.route_table_id]}).route_tables
    if rtbs.length == 1
      rtbs.first
    else
      raise "Did not find #{rtb.route_table_id}"
    end
  end

  def retrieve_nacl(subnet)
    nacls = @aws.describe_network_acls({filters: [{name: "vpc-id", values: [subnet.vpc_id]}]}).network_acls
    nacls = nacls.select { |nacl| nacl.associations.map { |assoc| assoc.subnet_id }.include? subnet.subnet_id }
    if nacls.length == 1
      nacls.first.is_default ? false : nacls.first
    else
      # This should be impossible
      raise "Did not find 1 nacl for #{subnet.subnet_id}, instead found #{nacls.length}"
    end
  end

  def reload_nacl(nacl)
    nacls = @aws.describe_network_acls({network_acl_ids: [nacl.network_acl_id]}).network_acls
    if nacls.length == 1
      nacls.first
    else
      # This should be impossible
      raise "Did not find 1 nacl for #{subnet.subnet_id}, instead found #{nacls.length}"
    end
  end

  def set_nacl(subnet, nacl)
    nacls = @aws.describe_network_acls({filters: [{name: "vpc-id", values: [subnet.vpc_id]}]}).network_acls
    current_nacls = nacls.select { |nacl| nacl.associations.map { |assoc| assoc.subnet_id }.include? subnet.subnet_id }
    unless current_nacls.length == 1
      # This should be impossible
      raise "Did not find 1 nacl for #{subnet.subnet_id}, instead found #{nacls.length}"
    end
    current_nacl = current_nacls.first
    assoc_ids = current_nacl.associations.select { |assoc| assoc.subnet_id == subnet.subnet_id }
    unless assoc_ids.length == 1
      # This should also be impossible
      raise "Did not find 1 nacl for #{subnet.subnet_id}, instead found #{nacls.length}"
    end
    assoc_id = assoc_ids[0].network_acl_association_id
    @aws.replace_network_acl_association({association_id: assoc_id, network_acl_id: nacl.network_acl_id})
  end

  def find_or_create_vpc(vpc_version = 'vpc-v0.1')
    vpc_name = 'oss-' + vpc_version
    # If the vpc exists check for configuration issues and state
    if retrieve_vpc(vpc_name)
      vpc = retrieve_vpc(vpc_name)
      # Ensure that the vpc has an IPV6 CIDR allocation
      if vpc.ipv_6_cidr_block_association_set.empty?
        raise "Found vpc #{vpc.vpc_id} with name #{vpc_name} but there is no allocated ipv6 CIDR block. Please delete #{vpc.vpc_id} to allow the vpc to be reconstructed."
      end
      if vpc.state == 'available'
        return vpc
      else
        logger.warn "Existing #{vpc.vpc_id} is not available. Deleting and recreating."
        @aws.delete_vpc({vpc_id: vpc.vpc_id})
      end
    end

    # Create and configure a new vpc with an IPV6 allocation
    vpc = @aws.create_vpc({cidr_block: '10.0.0.0/16', amazon_provided_ipv_6_cidr_block: true}).vpc
    begin
      @aws.wait_until(:vpc_available, vpc_ids: [vpc.vpc_id]) do |w|
        w.max_attempts = 4
      end
    rescue Aws::Waiters::Errors::WaiterFailed
      raise "ERROR: VPC #{vpc.vpc_id} did not become available within 60 seconds."
    end
    @aws.create_tags({
                         resources: [vpc.vpc_id],
                         tags: [{
                                    key: 'Name',
                                    value: vpc_name
                                }]
                     })
    reload_vpc(vpc)
  end

  def find_or_create_public_subnet(vpc, public_subnet_version = 'public-v0.1')
    # If the subnet exists check for configuration issues and state
    public_subnet_name = retrieve_vpc_name(vpc) + '-' + public_subnet_version
    if retrieve_subnet(public_subnet_name, vpc)
      public_subnet = retrieve_subnet(public_subnet_name, vpc)
      # Ensure that each instance launched in this subnet will receive a public IPV4 address on boot
      unless public_subnet.map_public_ip_on_launch
        raise "Public subnet (#{public_subnet.subnet_id}) does not have map_public_ip_on_launch enabled. Please delete #{public_subnet.subnet_id} to allow the subnet to be reconstructed."
      end
      # Ensure that the subnet is available before returning
      if public_subnet.state == 'available'
        return public_subnet
      else
        logger.warn "Existing public subnet #{public_subnet.subnet_id} is not available. Deleting and recreating."
        @aws.delete_subnet({subnet_id: public_subnet.subnet_id})
      end
    end

    # Create and configure a new subnet with map_public_ip_on_launch enabled
    public_subnet = @aws.create_subnet({
                                           cidr_block: '10.0.0.0/24',
                                           vpc_id: vpc.vpc_id
                                       }).subnet
    begin
      @aws.wait_until(:subnet_available, subnet_ids: [public_subnet.subnet_id]) do |w|
        w.max_attempts = 4
      end
    rescue Aws::Waiters::Errors::WaiterFailed
      raise "ERROR: Subnet #{public_subnet.subnet_id} did not become available within 60 seconds."
    end
    @aws.modify_subnet_attribute({
                                     subnet_id: public_subnet.subnet_id,
                                     map_public_ip_on_launch: {value: true}
                                 })
    @aws.create_tags({
                         resources: [public_subnet.subnet_id],
                         tags: [{
                                    key: 'Name',
                                    value: public_subnet_name
                                }]
                     })
    reload_subnet(public_subnet)
  end

  def find_or_create_private_subnet(vpc, private_subnet_version = 'private-v0.1')
    # If the subnet exists check for configuration issues and state
    private_subnet_name = retrieve_vpc_name(vpc) + '-' + private_subnet_version
    if retrieve_subnet(private_subnet_name, vpc)
      private_subnet = retrieve_subnet(private_subnet_name, vpc)
      # Ensure that the subnet has IPV6 enabled
      if private_subnet.ipv_6_cidr_block_association_set.empty?
        raise "Private subnet (#{private_subnet.subnet_id}) does not have an IPV6 CIDR block. This configuration is not supported."
      end
      # Ensure that all instances will receive an IPV6 address on creation
      unless private_subnet.assign_ipv_6_address_on_creation
        raise "Private subnet (#{private_subnet.subnet_id}) does not have assign_ipv_6_address_on_creation enabled. This configuration is not supported."
      end
      # Ensure the subnet is available before returning
      if private_subnet.state == 'available'
        return private_subnet
      else
        logger.warn "Existing private subnet #{private_subnet.subnet_id} is not available. Deleting and recreating."
        @aws.delete_subnet({subnet_id: private_subnet.subnet_id})
      end
    end

    # Create and configure a new IPV6 enabled subnet with assign_ipv_6_address_on_creation enabled
    vpc_ipv_6_block = vpc.ipv_6_cidr_block_association_set.first.ipv_6_cidr_block
    private_subnet_ipv_6_block = vpc_ipv_6_block.gsub('/56', '/64')
    private_subnet = @aws.create_subnet({
                                            cidr_block: '10.0.1.0/24',
                                            vpc_id: vpc.vpc_id,
                                            ipv_6_cidr_block: private_subnet_ipv_6_block
                                        }).subnet
    begin
      @aws.wait_until(:subnet_available, subnet_ids: [private_subnet.subnet_id]) do |w|
        w.max_attempts = 4
      end
    rescue Aws::Waiters::Errors::WaiterFailed
      raise "ERROR: Subnet #{private_subnet.subnet_id} did not become available within 60 seconds."
    end
    @aws.create_tags({
                         resources: [private_subnet.subnet_id],
                         tags: [{
                                    key: 'Name',
                                    value: private_subnet_name
                                }]
                     })
    private_subnet = reload_subnet(private_subnet)
    @aws.modify_subnet_attribute({
                                     subnet_id: private_subnet.subnet_id,
                                     assign_ipv_6_address_on_creation: {value: true}
                                 })
    reload_subnet(private_subnet)
  end

  def find_or_create_igw(vpc, igw_version = 'igw-v0.1')
    # If the igw exists check state
    igw_name = retrieve_vpc_name(vpc) + '-' + igw_version
    if retrieve_igw(vpc)
      igw = retrieve_igw(vpc)
      # Check state - only one attachment is allowed - the array is a templating artifact
      if igw.attachments.first.state == 'available'
        return igw
      else
        logger.warn "Existing #{igw.internet_gateway_id} attachment is not available. Deleting and recreating."
        @aws.detach_internet_gateway({internet_gateway_id: igw.internet_gateway_id, vpc_id: igw.attachments.first.vpc_id})
        @aws.delete_internet_gateway({internet_gateway_id: igw.internet_gateway_id})
      end
    end

    # Create and attach a new igw for the vpc
    igw_name = retrieve_vpc_name(vpc) + '-' + igw_version
    igw = @aws.create_internet_gateway.internet_gateway
    @aws.attach_internet_gateway({
                                     internet_gateway_id: igw.internet_gateway_id,
                                     vpc_id: vpc.vpc_id
                                 })
    @aws.create_tags({
                         resources: [igw.internet_gateway_id],
                         tags: [{
                                    key: 'Name',
                                    value: igw_name
                                }]
                     })
    reload_igw(igw)
  end

  def find_or_create_eigw(vpc)
    # This API is pretty simple, so this is quite easy
    if retrieve_eigw(vpc)
      retrieve_eigw(vpc)
    else
      @aws.create_egress_only_internet_gateway({vpc_id: vpc.vpc_id}).egress_only_internet_gateway
    end
  end

  def find_or_create_public_rtb(vpc, public_subnet, public_rtb_extension = 'rtb-public-v0.1')
    # If the rtb exists check that a route exists to the igw
    public_rtb_name = retrieve_vpc_name(vpc) + '-' + public_rtb_extension
    igw = retrieve_igw(vpc)
    if retrieve_rtb(public_subnet)
      public_rtb = retrieve_rtb(public_subnet)
      if public_rtb.routes.map{ |route| route.gateway_id }.include? igw.internet_gateway_id
        return public_rtb
      else
        # If a route points to 0.0.0.0/0 delete it, then add the igw route
        unless public_rtb.routes.select { |route| route.destination_cidr_block == '0.0.0.0/0' }.empty?
          @aws.delete_route({
                                destination_cidr_block: '0.0.0.0/0',
                                route_table_id: public_rtb.route_table_id,
                            })
        end
        @aws.create_route({
                              destination_cidr_block: '0.0.0.0/0',
                              gateway_id: igw.internet_gateway_id,
                              route_table_id: public_rtb.route_table_id
                          })
        return reload_rtb(public_rtb)
      end
    end

    # Create the standard public route table
    public_rtb = @aws.create_route_table({vpc_id: vpc.vpc_id}).route_table

    # Poor mans wait_for method - thanks aws-sdk-core for not addressing a known race condition nicely!!!
    waiting = true
    for _ in 0..11
      waiting = @aws.describe_route_tables({route_table_ids: [public_rtb.route_table_id]}).route_tables.empty?
      if waiting
        sleep(5)
      else
        break
      end
    end
    raise "rtb #{public_rtb.route_table_id} was not successfully created within 60 seconds" if waiting

    # Tag, associate, config, and return the new rtb
    @aws.create_tags({
                         resources: [public_rtb.route_table_id],
                         tags: [{
                                    key: 'Name',
                                    value: public_rtb_name
                                }]
                     })
    @aws.associate_route_table({
                                   route_table_id: public_rtb.route_table_id,
                                   subnet_id: public_subnet.subnet_id
                               })
    @aws.create_route({
                          destination_cidr_block: '0.0.0.0/0',
                          gateway_id: igw.internet_gateway_id,
                          route_table_id: public_rtb.route_table_id
                      })
    reload_rtb(public_rtb)
  end

  def find_or_create_private_rtb(vpc, private_subnet, private_rtb_extension = 'rtb-private-v0.1')
    # If the rtb exists check that a route exists to the eigw
    private_rtb_name = retrieve_vpc_name(vpc) + '-' + private_rtb_extension
    eigw = retrieve_eigw(vpc)
    if retrieve_rtb(private_subnet)
      private_rtb = retrieve_rtb(private_subnet)
      if private_rtb.routes.map{ |route| route.egress_only_internet_gateway_id }.include? eigw.egress_only_internet_gateway_id
        return private_rtb
      else
        # If a route points to 0.0.0.0/0 delete it, then add the igw route
        unless private_rtb.routes.select { |route| route.destination_ipv_6_cidr_block == '::/0' }.empty?
          @aws.delete_route({
                                destination_ipv_6_cidr_block: '::/0',
                                route_table_id: private_rtb.route_table_id,
                            })
        end
        @aws.create_route({
                              destination_ipv_6_cidr_block: '::/0',
                              egress_only_internet_gateway_id: eigw.egress_only_internet_gateway_id,
                              route_table_id: private_rtb.route_table_id
                          })
        return reload_rtb(private_rtb)
      end
    end

    # Create the standard private route table
    private_rtb = @aws.create_route_table({vpc_id: vpc.vpc_id}).route_table

    # Poor mans wait_for method - thanks aws-sdk-core for not addressing a known race condition nicely!!!
    waiting = true
    for _ in 0..11
      waiting = @aws.describe_route_tables({route_table_ids: [private_rtb.route_table_id]}).route_tables.empty?
      if waiting
        sleep(5)
      else
        break
      end
    end
    raise "rtb #{private_rtb.route_table_id} was not successfully created within 60 seconds" if waiting

    # Tag, associate, config, and return the new rtb
    @aws.create_tags({
                         resources: [private_rtb.route_table_id],
                         tags: [{
                                    key: 'Name',
                                    value: private_rtb_name
                                }]
                     })
    @aws.associate_route_table({
                                   route_table_id: private_rtb.route_table_id,
                                   subnet_id: private_subnet.subnet_id
                               })
    @aws.create_route({
                          destination_ipv_6_cidr_block: '::/0',
                          egress_only_internet_gateway_id: eigw.egress_only_internet_gateway_id,
                          route_table_id: private_rtb.route_table_id
                      })
    reload_rtb(private_rtb)
  end

  def find_or_create_public_nacl(vpc, public_subnet, public_nacl_extension = 'nacl-public-v0.1')
    # If the nacl exists verify ssh is enabled for this ip
    public_nacl_name = retrieve_vpc_name(vpc) + '-' + public_nacl_extension
    client_ip = retrieve_visible_ip
    # Client communication / access rules - TCP is protocol 6, UDP protocol 17
    client_rules = [
        {cidr: client_ip + '/32', egress: false, ports: [22, 22], protocol: '6', rule: 100},
        {cidr: client_ip + '/32', egress: false, ports: [27017, 27017], protocol: '6', rule: 110},
        {cidr: client_ip + '/32', egress: true, ports: [1025, 65535], protocol: '6', rule: 100},
        {cidr: '10.0.0.0/23', egress: true, ports: [22, 22], protocol: '6', rule: 110}
    ]
    # Docker swarm networking rules
    swarm_rules = [
        {cidr: '10.0.0.0/23', egress: false, ports: [2377, 2377], protocol: '6', rule: 200},
        {cidr: '10.0.0.0/23', egress: true, ports: [2377, 2377], protocol: '6', rule: 200},
        {cidr: '10.0.0.0/23', egress: false, ports: [4789, 4789], protocol: '17', rule: 210},
        {cidr: '10.0.0.0/23', egress: true, ports: [4789, 4789], protocol: '17', rule: 210},
        {cidr: '10.0.0.0/23', egress: false, ports: [7946, 7946], protocol: '6', rule: 220},
        {cidr: '10.0.0.0/23', egress: true, ports: [7946, 7946], protocol: '6', rule: 220},
        {cidr: '10.0.0.0/23', egress: false, ports: [7946, 7946], protocol: '17', rule: 230},
        {cidr: '10.0.0.0/23', egress: true, ports: [7946, 7946], protocol: '17', rule: 230}
    ]
    # Application resolution rules
    application_rules = [
        {cidr: '0.0.0.0/0', egress: false, ports: [80, 80], protocol: '6', rule: 300},
        {cidr: '0.0.0.0/0', egress: false, ports: [443, 443], protocol: '6', rule: 310},
        {cidr: '0.0.0.0/0', egress: false, ports: [32768, 60999], protocol: '6', rule: 320},
        {cidr: '0.0.0.0/0', egress: true, ports: [80, 80], protocol: '6', rule: 300},
        {cidr: '0.0.0.0/0', egress: true, ports: [443, 443], protocol: '6', rule: 310},
        {cidr: '0.0.0.0/0', egress: true, ports: [32768, 60999], protocol: '6', rule: 320}
    ]
    if retrieve_nacl(public_subnet)
      public_nacl = retrieve_nacl(public_subnet)
      rules_to_verify = client_rules + swarm_rules
      rules_to_apply = []
      entries = public_nacl.entries.select { |entry| entry.protocol != '-1' }
      ingress_rule_numbers = entries.select{ |rule| rule.egress == false }.map { |rule| rule.rule_number }
      ingress_rule_numbers.push(390) if ingress_rule_numbers.max < 390
      egress_rule_numbers = entries.select{ |rule| rule.egress == true }.map { |rule| rule.rule_number }
      egress_rule_numbers.push(390) if egress_rule_numbers.max < 390
      rules_to_verify.each do |rule|
        matching_rules = entries.select { |entry| (entry.cidr_block == rule[:cidr]) & (entry.egress == rule[:egress]) &
            (entry.port_range.from == rule[:ports][0]) & (entry.port_range.to == rule[:ports][1]) &
            (entry.protocol == rule[:protocol])}
        rules_to_apply.push(rule) if matching_rules.empty?
      end
      rules_to_apply.each do |rule|
        rule_number = (rule[:egress] ? egress_rule_numbers.max : egress_rule_numbers.max) + 10
        rule[:egress] ? egress_rule_numbers.push(rule_number) : ingress_rule_numbers.push(rule_number)
        @aws.create_network_acl_entry({
                                          cidr_block: rule[:cidr],
                                          egress: rule[:egress],
                                          network_acl_id: public_nacl.network_acl_id,
                                          port_range:{
                                              from: rule[:ports][0],
                                              to: rule[:ports][1]
                                          },
                                          protocol: rule[:protocol],
                                          rule_action: 'allow',
                                          rule_number: rule_number
                                      })
      end
      return reload_nacl(public_nacl)
    end

    # Create the public nacl within the VPC
    public_nacl = @aws.create_network_acl({vpc_id: vpc.vpc_id}).network_acl

    # Poor mans wait_for method - thanks aws-sdk-core for not addressing a known race condition nicely!!!
    waiting = true
    for _ in 0..11
      waiting = @aws.describe_network_acls({network_acl_ids: [public_nacl.network_acl_id]}).network_acls.empty?
      if waiting
        sleep(5)
      else
        break
      end
    end
    raise "nacl #{public_nacl.network_acl_id} was not successfully created within 60 seconds" if waiting

    # Tag and attach the public nacl
    @aws.create_tags({
                         resources: [public_nacl.network_acl_id],
                         tags: [{
                                    key: 'Name',
                                    value: public_nacl_name
                                }]
                     })
    set_nacl(public_subnet, public_nacl)
    # Set all rules
    rules_to_apply = client_rules + application_rules + swarm_rules
    rules_to_apply.each do |rule|
      @aws.create_network_acl_entry({
                                        cidr_block: rule[:cidr],
                                        egress: rule[:egress],
                                        network_acl_id: public_nacl.network_acl_id,
                                        port_range:{
                                            from: rule[:ports][0],
                                            to: rule[:ports][1]
                                        },
                                        protocol: rule[:protocol],
                                        rule_action: 'allow',
                                        rule_number: rule[:rule]
                                    })
    end
    reload_nacl(public_nacl)
  end

  def find_or_create_private_nacl(vpc, private_subnet, private_nacl_extension = 'nacl-private-v0.1')
    # If the nacl exists verify ssh is enabled for this ip
    private_nacl_name = retrieve_vpc_name(vpc) + '-' + private_nacl_extension
    client_ip = retrieve_visible_ip
    # Client communication / access rules - TCP is protocol 6, UDP protocol 17
    client_rules = [
        {cidr: '10.0.0.0/24', egress: false, ports: [22, 22], protocol: '6', rule: 100},
        {cidr: '10.0.0.0/24', egress: true, ports: [1025, 60999], protocol: '6', rule: 100}
    ]
    # Docker swarm networking rules
    swarm_rules = [
        {cidr: '10.0.0.0/23', egress: false, ports: [2377, 2377], protocol: '6', rule: 200},
        {cidr: '10.0.0.0/23', egress: true, ports: [2377, 2377], protocol: '6', rule: 200},
        {cidr: '10.0.0.0/23', egress: false, ports: [4789, 4789], protocol: '17', rule: 210},
        {cidr: '10.0.0.0/23', egress: true, ports: [4789, 4789], protocol: '17', rule: 210},
        {cidr: '10.0.0.0/23', egress: false, ports: [7946, 7946], protocol: '6', rule: 220},
        {cidr: '10.0.0.0/23', egress: true, ports: [7946, 7946], protocol: '6', rule: 220},
        {cidr: '10.0.0.0/23', egress: false, ports: [7946, 7946], protocol: '17', rule: 230},
        {cidr: '10.0.0.0/23', egress: true, ports: [7946, 7946], protocol: '17', rule: 230}
    ]
    # External IGW connection rules
    ipv6_rules = [
        {cidr: '::/0', egress: true, ports: [80, 80], protocol: '6', rule: 300},
        {cidr: '::/0', egress: true, ports: [443, 443], protocol: '6', rule: 310},
        {cidr: '::/0', egress: false, ports: [32768, 60999], protocol: '6', rule: 300}
    ]
    if retrieve_nacl(private_subnet)
      private_nacl = retrieve_nacl(private_subnet)
      rules_to_verify = client_rules + swarm_rules
      rules_to_apply = []
      entries = private_nacl.entries.select { |entry| entry.protocol != '-1' }
      ingress_rule_numbers = entries.select{ |rule| rule.egress == false }.map { |rule| rule.rule_number }
      ingress_rule_numbers.push(390) if ingress_rule_numbers.max < 390
      egress_rule_numbers = entries.select{ |rule| rule.egress == true }.map { |rule| rule.rule_number }
      egress_rule_numbers.push(390) if egress_rule_numbers.max < 390
      rules_to_verify.each do |rule|
        matching_rules = entries.select { |entry| (entry.cidr_block == rule[:cidr]) & (entry.egress == rule[:egress]) &
            (entry.port_range.from == rule[:ports][0]) & (entry.port_range.to == rule[:ports][1]) &
            (entry.protocol == rule[:protocol])}
        rules_to_apply.push(rule) if matching_rules.empty?
      end
      rules_to_apply.each do |rule|
        rule_number = (rule[:egress] ? egress_rule_numbers.max : egress_rule_numbers.max) + 10
        rule[:egress] ? egress_rule_numbers.push(rule_number) : ingress_rule_numbers.push(rule_number)
        @aws.create_network_acl_entry({
                                          cidr_block: rule[:cidr],
                                          egress: rule[:egress],
                                          network_acl_id: private_nacl.network_acl_id,
                                          port_range:{
                                              from: rule[:ports][0],
                                              to: rule[:ports][1]
                                          },
                                          protocol: rule[:protocol],
                                          rule_action: 'allow',
                                          rule_number: rule_number
                                      })
      end
      return reload_nacl(private_nacl)
    end

    # Create the private nacl within the VPC
    private_nacl = @aws.create_network_acl({vpc_id: vpc.vpc_id}).network_acl

    # Poor mans wait_for method - thanks aws-sdk-core for not addressing a known race condition nicely!!!
    waiting = true
    for _ in 0..11
      waiting = @aws.describe_network_acls({network_acl_ids: [private_nacl.network_acl_id]}).network_acls.empty?
      if waiting
        sleep(5)
      else
        break
      end
    end
    raise "nacl #{private_nacl.network_acl_id} was not successfully created within 60 seconds" if waiting

    # Tag and attach the private nacl
    @aws.create_tags({
                         resources: [private_nacl.network_acl_id],
                         tags: [{
                                    key: 'Name',
                                    value: private_nacl_name
                                }]
                     })
    set_nacl(private_subnet, private_nacl)
    # Set all IPV4 rules
    rules_to_apply = client_rules + swarm_rules
    rules_to_apply.each do |rule|
      @aws.create_network_acl_entry({
                                        cidr_block: rule[:cidr],
                                        egress: rule[:egress],
                                        network_acl_id: private_nacl.network_acl_id,
                                        port_range:{
                                            from: rule[:ports][0],
                                            to: rule[:ports][1]
                                        },
                                        protocol: rule[:protocol],
                                        rule_action: 'allow',
                                        rule_number: rule[:rule]
                                    })
    end
    # Set all IPV6 rules
    ipv6_rules.each do |rule|
      @aws.create_network_acl_entry({
                                        ipv_6_cidr_block: rule[:cidr],
                                        egress: rule[:egress],
                                        network_acl_id: private_nacl.network_acl_id,
                                        port_range:{
                                            from: rule[:ports][0],
                                            to: rule[:ports][1]
                                        },
                                        protocol: rule[:protocol],
                                        rule_action: 'allow',
                                        rule_number: rule[:rule]
                                    })
    end
    reload_nacl(private_nacl)
  end

  def remove_networking(vpc)
    # Initialize all networking infrastructure
    public_subnet = find_or_create_public_subnet(vpc)
    private_subnet = find_or_create_private_subnet(vpc)
    igw = retrieve_igw(vpc)
    eigw = retrieve_eigw(vpc)
    public_rtb = retrieve_rtb(public_subnet)
    private_rtb = retrieve_rtb(private_subnet)
    public_nacl = retrieve_nacl(public_subnet)
    private_nacl = retrieve_nacl(private_subnet)
    default_nacl = @aws.describe_network_acls({filters:
                                                   [
                                                       {name: 'default', values: ['true']},
                                                       {name: 'vpc-id', values: [vpc.vpc_id]}
                                                   ]
                                              }).network_acls[0]
    default_sg = create_or_retrieve_default_security_group(vpc_id: vpc.vpc_id)

    # First off delete the security group - this is sketchy and should be refactored as possible
    @aws.delete_security_group({group_id: default_sg.group_id})

    # Start by tearing down the private nacl
    if private_nacl
      set_nacl(private_subnet, default_nacl)
      private_nacl = reload_nacl(private_nacl)
      unless private_nacl.associations.empty?
        raise "nacl #{private_nacl.network_acl_id} is still associated with #{private_nacl.associations[0].subnet_id}"
      end
      @aws.delete_network_acl({network_acl_id: private_nacl.network_acl_id})
    end

    # Next tear down the public nacl
    if public_nacl
      set_nacl(public_subnet, default_nacl)
      public_nacl = reload_nacl(public_nacl)
      unless public_nacl.associations.empty?
        raise "nacl #{public_nacl.network_acl_id} is still associated with #{public_nacl.associations[0].subnet_id}"
      end
      @aws.delete_network_acl({network_acl_id: public_nacl.network_acl_id})
    end

    # Now goes the private rtb
    if private_rtb
      private_rtb = reload_rtb(private_rtb)
      unless private_rtb.associations.empty?
        private_rtb.associations.each { |assoc| @aws.disassociate_route_table({association_id: assoc.route_table_association_id})}
      end
      @aws.delete_route_table({route_table_id: private_rtb.route_table_id})
    end

    # And now the public rtb
    if public_rtb
      public_rtb = reload_rtb(public_rtb)
      unless public_rtb.associations.empty?
        public_rtb.associations.each { |assoc| @aws.disassociate_route_table({association_id: assoc.route_table_association_id})}
      end
      @aws.delete_route_table({route_table_id: public_rtb.route_table_id})
    end

    # Next remove the eigw
    if eigw
      @aws.delete_egress_only_internet_gateway({egress_only_internet_gateway_id: eigw.egress_only_internet_gateway_id})
    end

    # Followed by the igw
    if igw
      igw = reload_igw(igw)
      @aws.detach_internet_gateway({internet_gateway_id: igw.internet_gateway_id, vpc_id: vpc.vpc_id})
      @aws.delete_internet_gateway({internet_gateway_id: igw.internet_gateway_id})
    end

    # And now we finally reach the private subnet
    @aws.delete_subnet({subnet_id: private_subnet.subnet_id}) if private_subnet

    # Next the public subnet
    @aws.delete_subnet({subnet_id: public_subnet.subnet_id}) if public_subnet

    # And last but not least, the vpc itself
    sleep 5
    @aws.delete_vpc({vpc_id: vpc.vpc_id})
    true
  end

  def create_or_retrieve_default_security_group(tmp_name='openstudio-server-sg-v2.3', vpc_id=nil)
    if vpc_id
      group = @aws.describe_security_groups(filters: [{name: 'group-name', values: [tmp_name]}, {name: 'vpc-id', values: [vpc_id]}])
    else
      group = @aws.describe_security_groups(filters: [{name: 'group-name', values: [tmp_name]}])
    end
  end

  # Calculate the number of processors for the server and workers. This is used to scale the docker stack
  # appropriately.
  # @param total_procs [int] Total number of processors that are available
  def calculate_processors(total_procs)
    max_requests = ((total_procs + 10) * 1.2).round
    mongo_cores = (total_procs / 64.0).ceil
    web_cores = (total_procs / 32.0).ceil
    max_pool = 16 * web_cores
    rez_mem = 512 * max_pool
    # what is this +2 doing here
    total_procs = total_procs - mongo_cores - web_cores + 2

    [total_procs, max_requests, mongo_cores, web_cores, max_pool, rez_mem]
  end

  def create_or_retrieve_default_security_group(tmp_name='openstudio-server-sg-v2.2', vpc_id=nil)
    group = @aws.describe_security_groups(filters: [{ name: 'group-name', values: [tmp_name] }])
    logger.info "Length of the security group is: #{group.data.security_groups.length}"
    if group.data.security_groups.empty?
      logger.info 'security group not found --- will create a new one'
      if vpc_id
        r = @aws.create_security_group(group_name: tmp_name, description: "group dynamically created by #{__FILE__}",
                                       vpc_id: vpc_id)
      else
        r = @aws.create_security_group(group_name: tmp_name, description: "group dynamically created by #{__FILE__}")
      end
      group_id = r[:group_id]
      @aws.authorize_security_group_ingress(
          group_id: group_id,
          ip_permissions: [
              {ip_protocol: 'tcp', from_port: 22, to_port: 22, ip_ranges: [cidr_ip: '0.0.0.0/0']}, # Eventually make this only the user's IP address seen by the internet
              {ip_protocol: 'tcp', from_port: 80, to_port: 80, ip_ranges: [cidr_ip: '0.0.0.0/0']},
              {ip_protocol: 'tcp', from_port: 443, to_port: 443, ip_ranges: [cidr_ip: '0.0.0.0/0']},
              {ip_protocol: 'tcp', from_port: 27017, to_port: 27017, ip_ranges: [cidr_ip: '0.0.0.0/0']},
              {ip_protocol: 'tcp', from_port: 0, to_port: 65535, user_id_group_pairs: [{group_id: group_id}]}, # allow all machines in the security group talk to each other openly
              {ip_protocol: 'udp', from_port: 0, to_port: 65535, user_id_group_pairs: [{group_id: group_id}]}, # allow all machines in the security group talk to each other openly
              {ip_protocol: 'icmp', from_port: -1, to_port: -1, ip_ranges: [cidr_ip: '0.0.0.0/0']}
          ]
      )

      # reload group information
      group = @aws.describe_security_groups(filters: [{name: 'group-name', values: [tmp_name]}])
    else
      logger.info 'Found existing security group'
    end

    @security_groups = [group.data.security_groups.first.group_id]
    logger.info("server_group #{group.data.security_groups.first.group_name}:#{group.data.security_groups.first.group_id}")

    group.data.security_groups.first
  end

  def find_or_create_networking(vpc_id = false)
    logger.info "Creating networking infrastructure for OpenStudio Server"
    if vpc_id
      logger.info "Attempting to find existing vpc '#{vpc_id}'"
      vpcs = @aws.describe_vpcs({vpc_ids: [vpc_id]}).vpcs
      if vpcs.length != 1
        raise "Unable to retrieve vpc #{vpc_id}"
      end
      vpc = vpcs.first
      logger.info "Found vpc '#{vpc_id}'"
    else
      logger.info 'Creating a new vpc'
      vpc = find_or_create_vpc
      logger.info "Created vpc '#{vpc.vpc_id}'"
    end
    logger.info 'Creating or retrieving public subnet'
    public_subnet = find_or_create_public_subnet(vpc)
    logger.info "Created or retrieved public subnet '#{public_subnet.subnet_id}'"
    logger.info 'Creating or retrieving private subnet'
    private_subnet = find_or_create_private_subnet(vpc)
    logger.info "Created or retrieved private subnet '#{private_subnet.subnet_id}'"
    logger.info 'Creating or retrieving internet gateway'
    igw = find_or_create_igw(vpc)
    logger.info "Created or retrieved internet gateway '#{igw.internet_gateway_id}'"
    logger.info 'Creating or retrieving egress-only internet gateway'
    eigw = find_or_create_eigw(vpc)
    logger.info "Created or retrieved egress-only internet gateway '#{eigw.egress_only_internet_gateway_id}'"
    logger.info 'Creating or retrieving public route table'
    public_rtb = find_or_create_public_rtb(vpc, public_subnet)
    logger.info "Created or retrieved public route table '#{public_rtb.route_table_id}'"
    logger.info 'Creating or retrieving private route table'
    private_rtb = find_or_create_private_rtb(vpc, private_subnet)
    logger.info "Created or retrieved private route table '#{private_rtb.route_table_id}'"
    logger.info 'Creating or retrieving public network access control list'
    public_nacl = find_or_create_public_nacl(vpc, public_subnet)
    logger.info "Created or retrieved public network access control list '#{public_nacl.network_acl_id}'"
    logger.info 'Creating or retrieving private network access control list'
    private_nacl = find_or_create_private_nacl(vpc, private_subnet)
    logger.info "Created or retrieved private network access control list '#{private_nacl.network_acl_id}'"
    logger.info 'Creating the default security group in the vpc'
    default_sg = create_or_retrieve_default_security_group(vpc_id: vpc.vpc_id)
    logger.info "Created or retrieved default secuity group #{default_sg.group_id}"
    logger.info 'Finished configuring networking infrastructure'

    @public_subnet_id = public_subnet.subnet_id
    @private_subnet_id = private_subnet.subnet_id
    @security_groups = [default_sg.group_id]
    vpc.vpc_id
  end

  def describe_availability_zones
    resp = @aws.describe_availability_zones
    map = []
    resp.data.availability_zones.each do |zn|
      map << zn.to_hash
    end

    {availability_zone_info: map}
  end

  def describe_availability_zones_json
    describe_availability_zones.to_json
  end

  def total_instances_count
    resp = @aws.describe_instance_status

    availability_zone = !resp.instance_statuses.empty? ? resp.instance_statuses.first.availability_zone : 'no_instances'

    {total_instances: resp.instance_statuses.length, region: @region, availability_zone: availability_zone}
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
              {name: 'tag-key', values: ['GroupUUID']},
              {name: 'tag-value', values: [group_uuid.to_s]}
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
              {name: 'instance-state-code', values: [0.to_s, 16.to_s]}, # running or pending
              {name: 'tag-key', values: ['GroupUUID']},
              {name: 'tag-value', values: [group_uuid.to_s]}
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
      resp = {error: 'instances could not be found'}
    end

    resp
  end

  def create_or_retrieve_key_pair(key_pair_name = nil)
    tmp_name = key_pair_name || "os-key-pair-#{@group_uuid}"

    # the describe_key_pairs method will raise an expectation if it can't find the key pair, so catch it
    resp = nil
    begin
      resp = @aws.describe_key_pairs(key_names: [tmp_name]).data
      raise 'looks like there are 2 key pairs with the same name' if resp.key_pairs.size >= 2
    rescue StandardError
      logger.info "could not find key pair '#{tmp_name}'"
    end

    if resp.nil? || resp.key_pairs.empty?
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
    rescue StandardError
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
        raise "Could not find private key #{filename}" unless File.exist? filename
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
      File.chmod(0o600, @private_key_file_name)
    else
      raise "No private key found in which to persist with filename #{filename}"
    end
  end

  # save off the worker public/private keys that were created
  def save_worker_keys(directory = '.')
    @worker_keys_filename = "#{directory}/ec2_worker_key.pem"
    logger.info "Saving worker private key in #{@worker_keys_filename}"
    File.open(@worker_keys_filename, 'w') { |f| f << @worker_keys.private_key }
    logger.info 'Setting permissions of worker private key to 0600'
    File.chmod(0o600, @worker_keys_filename)

    wk = "#{directory}/ec2_worker_key.pub"
    logger.info "Saving worker public key in #{wk}"
    File.open(wk, 'w') { |f| f << @worker_keys.public_key }
  end

  def launch_server(image_id, instance_type, launch_options = {})
    defaults = {
        user_id: 'unknown_user',
        tags: [],
        ebs_volume_size: nil,
        user_data_file: 'server_script.sh.template',
        vpc_enabled: false
    }
    launch_options = defaults.merge(launch_options)

    # ensure networking infrastructure exists if required
    if launch_options[:vpc_enabled]
      find_or_create_networking
      if @public_subnet_id.nil?
        raise 'The method find_or_create_networking did not instantiate the @public_subnet_id variable. Please file redundant issues in the OpenStudio-Aws-Gem and OpenStudio-Server github repositories'
      end
      if launch_options[:subnet_id]
        if launch_options[:subnet_id] != @public_subnet_id
          raise "The subnet_id provided in launch options, #{launch_options[:subnet_id]}, differs from the retrieved VPC configuration, #{@public_subnet_id}"
        end
      end
      launch_options[:subnet_id] = @public_subnet_id
    end

    # replace the server_script.sh.template with the keys to add

    user_data = File.read(File.join(__dir__, launch_options[:user_data_file]))
    user_data.gsub!(/SERVER_HOSTNAME/, 'openstudio.server')
    user_data.gsub!(/WORKER_PRIVATE_KEY_TEMPLATE/, worker_keys.private_key.gsub("\n", '\\n'))
    user_data.gsub!(/WORKER_PUBLIC_KEY_TEMPLATE/, worker_keys.ssh_public_key)

    @server = OpenStudioAwsInstance.new(@aws, :server, @key_pair_name, @security_groups, @group_uuid, @private_key,
                                        @private_key_file_name, @proxy)

    # TODO: create the EBS volumes instead of the ephemeral storage - needed especially for the m3 instances (SSD)

    raise 'image_id is nil' unless image_id
    raise 'instance type is nil' unless instance_type

    @server.launch_instance(image_id, instance_type, user_data, launch_options[:user_id], launch_options)
  end

  def launch_workers(image_id, instance_type, num, launch_options = {})
    defaults = {
        user_id: 'unknown_user',
        tags: [],
        ebs_volume_size: nil,
        availability_zone: @server.data.availability_zone,
        user_data_file: 'worker_script.sh.template',
        vpc_enabled: false
    }
    launch_options = defaults.merge(launch_options)

    user_data = File.read(File.join(__dir__, launch_options[:user_data_file]))
    user_data.gsub!(/SERVER_IP/, @server.data.private_ip_address)
    user_data.gsub!(/SERVER_HOSTNAME/, 'openstudio.server')
    user_data.gsub!(/WORKER_PUBLIC_KEY_TEMPLATE/, worker_keys.ssh_public_key)
    logger.info("worker user_data #{user_data.inspect}")

    # thread the launching of the workers
    num.times do
      @workers << OpenStudioAwsInstance.new(@aws, :worker, @key_pair_name, @security_groups, @group_uuid,
                                            @private_key, @private_key_file_name, @proxy)
    end

    # config vpc networking infrastructure settings if required
    if launch_options[:vpc_enabled]
      if @private_subnet_id.nil?
        raise 'The method find_or_create_networking did not instantiate the @private_subnet_id variable. Please file redundant issues in the OpenStudio-Aws-Gem and OpenStudio-Server github repositories'
      end
      if launch_options[:subnet_id]
        if launch_options[:subnet_id] != @private_subnet_id
          raise "The subnet_id provided in launch options, #{launch_options[:subnet_id]}, differs from the retrieved VPC configuration, #{@private_subnet_id}"
        end
      end
      launch_options[:subnet_id] = @private_subnet_id
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

    mongoid = File.read(__dir__ + '/mongoid.yml.template')
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

  # blocking method that executes required commands for creating and provisioning a docker swarm cluster
  def configure_swarm_cluster(save_directory, vpc_enabled = false)
    logger.info('waiting for server user_data to complete')
    @server.wait_command('while ! [ -e /home/ubuntu/user_data_done ]; do sleep 5; done && echo "true"')
    logger.info('Running the configuration script for the server.')
    @server.wait_command('echo $(env) &> /home/ubuntu/env.log && echo "true"')
    @server.wait_command('cp /home/ubuntu/server_provision.sh /home/ubuntu/server_provision.sh.bak && echo "true"')
    @server.wait_command('sudo /home/ubuntu/server_provision.sh &> /home/ubuntu/server_provision.log && echo "true"')
    logger.info('Downloading the swarm join command.')
    swarm_file = File.join(save_directory, 'worker_swarm_join.sh')
    @server.download_file('/home/ubuntu/swarmjoin.sh', swarm_file)
    logger.info('waiting for worker user_data to complete')
    @workers.each { |worker| worker.wait_command('while ! [ -e /home/ubuntu/user_data_done ]; do sleep 5; done && echo "true"') }
    logger.info('Running the configuration script for the worker(s).')
    @workers.each { |worker| worker.wait_command('sudo /home/ubuntu/worker_provision.sh &> /home/ubuntu/worker_provision.log && echo "true"') }
    logger.info('Successfully re-sized storage devices for all nodes. Joining server nodes to the swarm.')
    worker_join_cmd = "#{File.read(swarm_file).strip} && echo \"true\""
    @workers.each { |worker| worker.wait_command(worker_join_cmd) }
    logger.info('All worker nodes have been added to the swarm. Setting environment variables and starting the cluster')
    # e.g. 356 CPUs
    # mongo cores = 6
    # web cores = 12
    # total procs = 340 (but should be 336)
    total_procs = @server.procs
    @workers.each { |worker| total_procs += worker.procs }
    total_procs, max_requests, mongo_cores, web_cores, max_pool, rez_mem = calculate_processors(total_procs)
    logger.info('Processors allocations are:')
    logger.info("   total_procs: #{total_procs}")
    logger.info("   max_requests: #{max_requests}")
    logger.info("   mongo_cores: #{mongo_cores}")
    logger.info("   web_cores: #{web_cores}")
    logger.info("   max_pool: #{max_pool}")
    logger.info("   rez_mem: #{rez_mem}")
    @server.shell_command("sed -i -e 's/AWS_MAX_REQUESTS/#{max_requests}/g' /home/ubuntu/docker-compose.yml && echo \"true\"")
    @server.shell_command("sed -i -e 's/AWS_MONGO_CORES/#{mongo_cores}/g' /home/ubuntu/docker-compose.yml && echo \"true\"")
    @server.shell_command("sed -i -e 's/AWS_WEB_CORES/#{web_cores}/g' /home/ubuntu/docker-compose.yml && echo \"true\"")
    @server.shell_command("sed -i -e 's/AWS_MAX_POOL/#{max_pool}/g' /home/ubuntu/docker-compose.yml && echo \"true\"")
    @server.shell_command("sed -i -e 's/AWS_REZ_MEM/#{rez_mem}/g' /home/ubuntu/docker-compose.yml && echo \"true\"")
    @server.shell_command("sed -i -e 's/AWS_OS_SERVER_NUMBER_OF_WORKERS/#{total_procs}/g' /home/ubuntu/docker-compose.yml && echo \"true\"")
    @server.shell_command("echo '' >> /home/ubuntu/.env && echo \"true\"")
    @server.shell_command('docker stack deploy --compose-file docker-compose.yml osserver && echo "true"')
    sleep 10
    logger.info('The OpenStudio Server stack has been started. Waiting for the server to become available.')
    @server.wait_command("while ( nc -zv #{@server.ip} 80 3>&1 1>&2- 2>&3- ) | awk -F \":\" '$3 != \" Connection refused\" {exit 1}'; do sleep 5; done && echo \"true\"")
    logger.info('The OpenStudio Server stack has become available. Scaling the worker nodes.')
    @server.wait_command("docker service scale osserver_worker=#{total_procs} && echo \"true\"")
    logger.info('Waiting up to two minutes for the osserver_worker service to scale.')
    @server.wait_command("timeout 120 bash -c -- 'while [ $( docker service ls -f name=osserver_worker --format=\"{{.Replicas}}\" ) != \"#{total_procs}/#{total_procs}\" ]; do sleep 5; done'; echo \"true\"")
    logger.info('The OpenStudio Server stack is booted and ready for analysis submissions.')
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
    raise 'no GroupUUID defined either in member variable or method argument' if @group_uuid.nil?

    # This should really just be a single call to describe running instances
    @server = nil
    resp = describe_running_instances(group_uuid, :server)
    if resp
      raise "more than one server running with group uuid of #{group_uuid} found, expecting only one" if resp.size > 1

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
          @key_pair_name ||= resp[:key_name]

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
    if @workers.empty?
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
    amis = {openstudio_server: {}, openstudio: {}}
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
            raise "unknown virtualization_type in #{ami[:name]}"
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
