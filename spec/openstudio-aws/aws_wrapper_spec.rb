# This spec file contains the testing of OpenStudio specific tests (for AMI listing) which require an AWS account and authentication
require 'spec_helper'

describe OpenStudioAwsWrapper do
  context 'unauthenticated session' do
    it 'should fail to authenticate' do
      options = {
        credentials: {
          access_key_id: 'some_random_access_key_id',
          secret_access_key: 'some_super_secret_access_key',
          region: 'us-east-1',
          ssl_verify_peer: false
        }
      }

      @os_aws = OpenStudioAwsWrapper.new(options)
      expect { @os_aws.describe_availability_zones }.to raise_exception
    end
  end

  context 'authenticated session' do
    before :all do
      @aws = OpenStudio::Aws::Aws.new
    end

    context 'new instance' do
      it 'should be created' do
        expect(@aws.os_aws).not_to be_nil
      end
    end

    context 'availability' do
      it 'should describe the zones' do
        resp = @aws.os_aws.describe_availability_zones
        expect(resp).not_to be_nil
        expect(resp[:availability_zone_info].length).to eq(5)

        expect(resp[:availability_zone_info].inspect).to eq("[{:zone_name=>\"us-east-1a\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1b\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1c\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1d\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1e\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}]")

        resp = @aws.os_aws.describe_availability_zones_json
        expect(resp).not_to be_nil
      end

      it 'should list number of instances' do
        resp = @aws.os_aws.total_instances_count
        expect(resp).not_to be_nil
      end
    end

    context 'create new ami json' do
      it 'should describe existing AMIs' do
        resp = @aws.os_aws.describe_amis
        expect(resp[:images].length).to be >= 10
      end

      it 'should describe a specific image' do
        resp = @aws.os_aws.describe_amis(['ami-39bb8750'], false)
        expect(resp[:images].first[:image_id]).to eq('ami-39bb8750')
        expect(resp[:images].first[:tags_hash][:user_uuid]).to eq('jenkins-139LADFJ178')
        expect(resp[:images].first[:tags_hash][:openstudio_server_version]).to eq('1.3.1')
      end
    end

    context 'version 1' do
      it 'should create a new json and return the right server versions' do
        resp = @aws.os_aws.create_new_ami_json(1)
        expect(resp['1.2.1'.to_sym][:server]).to eq('ami-89744be0')
        expect(resp['1.9.0'.to_sym][:server]).to eq('ami-f3611996')
        expect(resp['default'.to_sym][:server]).to_not eq('ami-89744be0')
      end
    end

    context 'version 2' do
      it 'should create a new json' do
        resp = @aws.os_aws.create_new_ami_json(2)
        expect(resp[:openstudio_server]['1.21.4'.to_sym][:amis][:server]).to eq('ami-e7a1bbf0')
        expect(resp[:openstudio_server]['1.21.4'.to_sym][:openstudio_version_sha]).to eq('6103d54380')
        expect(resp[:openstudio_server]['1.21.4'.to_sym][:tested]).to eq(false)
      end
    end
  end

  context 'ami list' do
    before :all do
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should get the next version' do
      expect(@aws.os_aws.get_next_version('0.1.1', [])).to eq('0.1.1')
      expect(@aws.os_aws.get_next_version('0.1.1', ['0.1.1'])).to eq('0.1.2')
      expect(@aws.os_aws.get_next_version('0.1.1', ['0.1.1', '0.1.3'])).to eq('0.1.4')
      expect(@aws.os_aws.get_next_version('0.1.1', ['0.1.1', '0.1.2', '0.1.3'])).to eq('0.1.4')
      expect(@aws.os_aws.get_next_version('0.1.1', ['0.1.1', '0.1.2', '0.1.3', '0.1.15'])).to eq('0.1.16')
      expect(@aws.os_aws.get_next_version('0.1.1', ['0.1.1', '0.1.2', '0.1.3', '0.1.15', '3.1.0'])).to eq('0.1.16')
      expect(@aws.os_aws.get_next_version('0.1.1', ['0.1.1', '0.1.2', '0.1.3', '0.1.15', '3.1.27'])).to eq('0.1.16')
    end
  end

  context 'security groups' do
    before :all do
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should create security group' do
      sg = @aws.os_aws.create_or_retrieve_default_security_group
      expect(sg).to_not be nil
    end
  end

  context 'vpc methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
    end

    before :each do
      @vpc = false
      @vpc_2 = false
      expect(@osaws.os_aws.retrieve_vpc('oss-vpc-v0.1')).to eq(false)
    end

    it 'should create a simple vpc' do
      # If this doesn't work, check your iam permissions and account info
      @vpc = @client.create_vpc({cidr_block: '10.0.0.0/16'}).vpc
      expect{@client.wait_until(:vpc_available, vpc_ids: [@vpc.vpc_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
    end

    it 'should create and retrieve a new vpc' do
      expect{@vpc = @osaws.os_aws.find_or_create_vpc}.to_not raise_error
      expect(@osaws.os_aws.retrieve_vpc('oss-vpc-v0.1').vpc_id).to eq(@vpc.vpc_id)
    end

    it 'should find an already existing vpc' do
      expect{@vpc = @osaws.os_aws.find_or_create_vpc}.to_not raise_error
      @vpc_2 = @osaws.os_aws.find_or_create_vpc
      expect(@vpc_2.vpc_id).to eq(@vpc.vpc_id)
    end

    it 'should error out if the existing oss-vpc-v0.1 has no IPV6 CIDR allocation' do
      @vpc = @client.create_vpc({cidr_block: '10.0.0.0/16', amazon_provided_ipv_6_cidr_block: false}).vpc
      expect{@client.wait_until(:vpc_available, vpc_ids: [@vpc.vpc_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@vpc.vpc_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.find_or_create_vpc}.to raise_error(RuntimeError)
    end

    it 'should fail to retrieve the vpc if two vpcs with that name tag exist' do
      expect{@vpc = @osaws.os_aws.find_or_create_vpc}.to_not raise_error
      @vpc_2 = @client.create_vpc({cidr_block: '10.0.0.0/16'}).vpc
      expect{@client.wait_until(:vpc_available, vpc_ids: [@vpc_2.vpc_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@vpc_2.vpc_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.retrieve_vpc('oss-vpc-v0.1')}.to raise_error(RuntimeError)
    end

    after :each do
      @client.delete_vpc({vpc_id: @vpc.vpc_id}) if @vpc
      if @vpc_2
        @client.delete_vpc({vpc_id: @vpc_2.vpc_id}) if (@vpc_2.vpc_id != @vpc.vpc_id)
      end
    end

    after :all do
      vpcs = @client.describe_vpcs(filters: [{name: 'tag-key', values: ['Name']}, {name: 'tag-value', values: ['oss-vpc-v0.1']}]).vpcs
      vpcs.each do |vpc|
        @client.delete_vpc({vpc_id: vpc.vpc_id})
      end
    end
  end

  context 'public subnet methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      expect(@osaws.os_aws.retrieve_vpc('oss-vpc-v0.1')).to eq(false)
      @vpc = @osaws.os_aws.find_or_create_vpc
      @client = @osaws.os_aws.instance_variable_get(:@aws)
    end

    before :each do
      expect(@osaws.os_aws.retrieve_subnet('oss-vpc-v0.1-public-v0.1', @vpc)).to be false
      @subnet = false
      @subnet_2 = false
    end

    it 'should create a simple subnet' do
      # If this doesn't work check your iam permissions and account info
      @subnet = @client.create_subnet({cidr_block: '10.0.0.0/24', vpc_id: @vpc.vpc_id}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
    end

    it 'should create and retrieve a public subnet' do
      expect{@subnet = @osaws.os_aws.find_or_create_public_subnet(@vpc)}.to_not raise_error
      expect(@osaws.os_aws.retrieve_subnet('oss-vpc-v0.1-public-v0.1', @vpc).subnet_id).to eq(@subnet.subnet_id)
    end

    it 'should find an already existing public subnet' do
      expect{@subnet = @osaws.os_aws.find_or_create_public_subnet(@vpc)}.to_not raise_error
      @subnet_2 = @osaws.os_aws.find_or_create_public_subnet(@vpc)
      expect(@subnet_2.subnet_id).to eq(@subnet.subnet_id)
    end

    it 'should error out if the existing public subnet does not auto-assign public IPV4 addresses' do
      @subnet = @client.create_subnet({cidr_block: '10.0.0.0/24', vpc_id: @vpc.vpc_id}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@subnet.subnet_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1-public-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.find_or_create_public_subnet(@vpc)}.to raise_error(RuntimeError)
    end

    it 'should fail to retrieve the subnet if two subnets with the same name tag exist in the vpc' do
      expect{@subnet = @osaws.os_aws.find_or_create_public_subnet(@vpc)}.to_not raise_error
      @subnet_2 = @client.create_subnet({cidr_block: '10.0.1.0/24', vpc_id: @vpc.vpc_id}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet_2.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@subnet_2.subnet_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1-public-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.retrieve_subnet('oss-vpc-v0.1-public-v0.1', @vpc)}.to raise_error(RuntimeError)
    end

    after :each do
      @client.delete_subnet({subnet_id: @subnet.subnet_id}) if @subnet
      if @subnet_2
        @client.delete_subnet({subnet_id: @subnet_2.subnet_id}) if (@subnet_2.subnet_id != @subnet.subnet_id)
      end
    end

    after :all do
      subnets = @client.describe_subnets(filters: [{name: 'tag-key', values: ['Name']}, {name: 'tag-value', values: ['oss-vpc-v0.1-public-v0.1']}, {name: 'vpc-id', values: [@vpc.vpc_id]}]).subnets
      subnets.each do |subnet|
        @client.delete_subnet({subnet_id: subnet.subnet_id})
      end
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'private subnet methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      expect(@osaws.os_aws.retrieve_vpc('oss-vpc-v0.1')).to eq(false)
      @vpc = @osaws.os_aws.find_or_create_vpc
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      vpc_ipv_6_block = @vpc.ipv_6_cidr_block_association_set.first.ipv_6_cidr_block
      @ipv_6_block = vpc_ipv_6_block.gsub('/56', '/64')

    end

    before :each do
      expect(@osaws.os_aws.retrieve_subnet('oss-vpc-v0.1-private-v0.1', @vpc)).to be false
      @subnet = false
      @subnet_2 = false
    end

    it 'should create a simple subnet' do
      # If this doesn't work check your iam permissions and account info
      @subnet = @client.create_subnet({cidr_block: '10.0.0.0/24', vpc_id: @vpc.vpc_id, ipv_6_cidr_block: @ipv_6_block}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
    end

    it 'should create and retrieve a private subnet' do
      expect{@subnet = @osaws.os_aws.find_or_create_private_subnet(@vpc)}.to_not raise_error
      expect(@osaws.os_aws.retrieve_subnet('oss-vpc-v0.1-private-v0.1', @vpc).subnet_id).to eq(@subnet.subnet_id)
    end

    it 'should find an already existing private subnet' do
      expect{@subnet = @osaws.os_aws.find_or_create_private_subnet(@vpc)}.to_not raise_error
      @subnet_2 = @osaws.os_aws.find_or_create_private_subnet(@vpc)
      expect(@subnet_2.subnet_id).to eq(@subnet.subnet_id)
    end

    it 'should error out if the existing private subnet does not have an IPV6 CIDR block' do
      @subnet = @client.create_subnet({cidr_block: '10.0.2.0/24', vpc_id: @vpc.vpc_id}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@subnet.subnet_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1-private-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.find_or_create_private_subnet(@vpc)}.to raise_error(RuntimeError)
    end

    it 'should error out if the existing private subnet does not auto-assign IPV6 addresses' do
      @subnet = @client.create_subnet({cidr_block: '10.0.0.0/24', vpc_id: @vpc.vpc_id, ipv_6_cidr_block: @ipv_6_block}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@subnet.subnet_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1-private-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.find_or_create_private_subnet(@vpc)}.to raise_error(RuntimeError)
    end

    it 'should fail to retrieve the subnet if two subnets with the same name tag exist in the vpc' do
      expect{@subnet = @osaws.os_aws.find_or_create_private_subnet(@vpc)}.to_not raise_error
      @subnet_2 = @client.create_subnet({cidr_block: '10.0.2.0/24', vpc_id: @vpc.vpc_id}).subnet
      expect{@client.wait_until(:subnet_available, subnet_ids: [@subnet_2.subnet_id]){ |w| w.max_attempts = 4 }}.to_not raise_error
      @client.create_tags({
                           resources: [@subnet_2.subnet_id],
                           tags: [{
                                      key: 'Name',
                                      value: 'oss-vpc-v0.1-private-v0.1'
                                  }]
                       })
      expect{@osaws.os_aws.retrieve_subnet('oss-vpc-v0.1-private-v0.1', @vpc)}.to raise_error(RuntimeError)
    end

    after :each do
      @client.delete_subnet({subnet_id: @subnet.subnet_id}) if @subnet
      if @subnet_2
        @client.delete_subnet({subnet_id: @subnet_2.subnet_id}) if (@subnet_2.subnet_id != @subnet.subnet_id)
      end
    end

    after :all do
      subnets = @client.describe_subnets(filters: [{name: 'tag-key', values: ['Name']}, {name: 'tag-value', values: ['oss-vpc-v0.1-public-v0.1']}, {name: 'vpc-id', values: [@vpc.vpc_id]}]).subnets
      subnets.each do |subnet|
        @client.delete_subnet({subnet_id: subnet.subnet_id})
      end
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'igw methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      @vpc = @osaws.os_aws.find_or_create_vpc
    end

    before :each do
      expect(@osaws.os_aws.retrieve_igw('oss-vpc-v0.1-igw-v0.1', @vpc)).to be false
      @igw = false
      @igw_2 = false
    end

    it 'should create and attach an igw' do
      # If this doesn't work check your igw IAM permissions and credentials
      expect{@igw = @client.create_internet_gateway.internet_gateway}.to_not raise_error
      expect{@client.attach_internet_gateway({
                                                 internet_gateway_id: @igw.internet_gateway_id,
                                                 vpc_id: @vpc.vpc_id
                                             })}.to_not raise_error
    end

    it 'should create and retrieve an igw' do
      expect{@igw = @osaws.os_aws.find_or_create_igw(@vpc)}.to_not raise_error
      expect(@osaws.os_aws.retrieve_igw('oss-vpc-v0.1-igw-v0.1', @vpc).internet_gateway_id).to eq(@igw.internet_gateway_id)
    end

    it 'should find an already existing igw' do
      expect{@igw = @osaws.os_aws.find_or_create_igw(@vpc)}.to_not raise_error
      @igw_2 = @osaws.os_aws.find_or_create_igw(@vpc)
      expect(@igw.internet_gateway_id).to eq(@igw_2.internet_gateway_id)
    end

    it 'should error when the attached igw is not named oss-vpc-v0.1-igw-v0.1' do

    end

    after :each do
      if @igw
        @igw = @osaws.os_aws.reload_igw(@igw)
        @client.detach_internet_gateway({internet_gateway_id: @igw.internet_gateway_id, vpc_id: @igw.attachments.first.vpc_id})
        @client.delete_internet_gateway({internet_gateway_id: @igw.internet_gateway_id})
      end
      if @igw_2
        if @igw.internet_gateway_id != @igw_2.internet_gateway_id
          @igw_2 = @osaws.os_aws.reload_igw(@igw_2)
          @client.detach_internet_gateway({internet_gateway_id: @igw_2.internet_gateway_id, vpc_id: @igw_2.attachments.first.vpc_id})
          @client.delete_internet_gateway({internet_gateway_id: @igw_2.internet_gateway_id})
        end
      end
    end

    after :all do
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'eigw methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      @vpc = @osaws.os_aws.find_or_create_vpc
    end

    before :each do
      expect(@osaws.os_aws.retrieve_eigw(@vpc)).to be false
      @eigw = false
      @eigw_2 = false
    end

    it 'should create and attach an eigw' do
      # If this doesn't work check your eigw IAM permissions and credentials
      expect{@eigw = @client.create_egress_only_internet_gateway({vpc_id: @vpc.vpc_id}).egress_only_internet_gateway}.to_not raise_error
    end

    it 'should create and retrieve an eigw' do
      expect{@eigw = @osaws.os_aws.find_or_create_eigw(@vpc)}.to_not raise_error
      expect(@osaws.os_aws.retrieve_eigw(@vpc).egress_only_internet_gateway_id).to eq(@eigw.egress_only_internet_gateway_id)
    end

    it 'should find an already existing eigw' do
      expect{@eigw = @osaws.os_aws.find_or_create_eigw(@vpc)}.to_not raise_error
      @eigw_2 = @osaws.os_aws.find_or_create_eigw(@vpc)
      expect(@eigw.egress_only_internet_gateway_id).to eq(@eigw_2.egress_only_internet_gateway_id)
    end

    after :each do
      @client.delete_egress_only_internet_gateway({egress_only_internet_gateway_id: @eigw.egress_only_internet_gateway_id}) if @eigw
      if @eigw_2
        if @eigw.egress_only_internet_gateway_id != @eigw_2.egress_only_internet_gateway_id
          @client.delete_egress_only_internet_gateway({egress_only_internet_gateway_id: @eigw_2.egress_only_internet_gateway_id})
        end
      end
    end

    after :all do
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'public rtb methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      @vpc = @osaws.os_aws.find_or_create_vpc
      @subnet = @osaws.os_aws.find_or_create_public_subnet(@vpc)
      @igw = @osaws.os_aws.find_or_create_igw(@vpc)
    end

    before :each do
      expect(@osaws.os_aws.retrieve_rtb(@subnet)).to be false
      @rtb = false
      @rtb_2 = false
    end

    it 'should create and associate a public rtb' do
      expect{@rtb = @client.create_route_table({vpc_id: @vpc.vpc_id}).route_table}.to_not raise_error
      expect{@client.associate_route_table({route_table_id: @rtb.route_table_id, subnet_id: @subnet.subnet_id})}.to_not raise_error
    end

    it 'should reflect changes upon reloading the public rtb' do
      expect{@rtb = @client.create_route_table({vpc_id: @vpc.vpc_id}).route_table}.to_not raise_error
      expect{@client.associate_route_table({route_table_id: @rtb.route_table_id, subnet_id: @subnet.subnet_id})}.to_not raise_error
      expect(@rtb.associations.empty?).to be true
      expect(@osaws.os_aws.reload_rtb(@rtb).associations.first.subnet_id).to eq(@subnet.subnet_id)
    end

    it 'should create and retrieve an existing public rtb' do
      expect{@rtb = @osaws.os_aws.find_or_create_public_rtb(@vpc, @subnet)}.to_not raise_error
      expect(@osaws.os_aws.retrieve_rtb(@subnet).route_table_id).to eq(@rtb.route_table_id)
    end

    it 'should find an already existing public rtb' do
      expect{@rtb = @osaws.os_aws.find_or_create_public_rtb(@vpc, @subnet)}.to_not raise_error
      @rtb_2 = @osaws.os_aws.find_or_create_public_rtb(@vpc, @subnet)
      expect(@rtb.route_table_id).to eq(@rtb_2.route_table_id)
    end

    it 'should self-heal if missing a route to the igw in the public rtb' do
      expect{@rtb = @osaws.os_aws.find_or_create_public_rtb(@vpc, @subnet)}.to_not raise_error
      @client.delete_route({destination_cidr_block: "0.0.0.0/0", route_table_id: @rtb.route_table_id})
      @rtb = @osaws.os_aws.reload_rtb(@rtb)
      expect(@rtb.routes.select { |route| route.gateway_id == @igw.internet_gateway_id }.empty?).to be true
      expect{@rtb = @osaws.os_aws.find_or_create_public_rtb(@vpc, @subnet)}.to_not raise_error
      expect(@rtb.routes.select { |route| route.gateway_id == @igw.internet_gateway_id }.empty?).to be false
    end

    after :each do
      if @rtb
        @rtb = @osaws.os_aws.reload_rtb(@rtb)
        unless @rtb.associations.empty?
          @rtb.associations.each { |assoc| @client.disassociate_route_table({association_id: assoc.route_table_association_id})}
        end
        @client.delete_route_table({route_table_id: @rtb.route_table_id})
      end
      if @rtb_2
        if @rtb_2.route_table_id != @rtb.route_table_id
          @rtb_2 = @osaws.os_aws.reload_rtb(@rtb_2)
          unless @rtb_2.associations.empty?
            @rtb.associations.each { |assoc| @client.disassociate_route_table({association_id: assoc.route_table_association_id})}
          end
          @client.delete_route_table({route_table_id: @rtb_2.route_table_id})
        end
      end
    end

    after :all do
      @igw = @osaws.os_aws.reload_igw(@igw)
      @client.detach_internet_gateway({internet_gateway_id: @igw.internet_gateway_id, vpc_id: @vpc.vpc_id})
      @client.delete_internet_gateway({internet_gateway_id: @igw.internet_gateway_id})
      @client.delete_subnet({subnet_id: @subnet.subnet_id})
      sleep 2
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'private rtb methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      @vpc = @osaws.os_aws.find_or_create_vpc
      @subnet = @osaws.os_aws.find_or_create_private_subnet(@vpc)
      @eigw = @osaws.os_aws.find_or_create_eigw(@vpc)
    end

    before :each do
      expect(@osaws.os_aws.retrieve_rtb(@subnet)).to be false
      @rtb = false
      @rtb_2 = false
    end

    it 'should create and associate a private rtb' do
      expect{@rtb = @client.create_route_table({vpc_id: @vpc.vpc_id}).route_table}.to_not raise_error
      expect{@client.associate_route_table({route_table_id: @rtb.route_table_id, subnet_id: @subnet.subnet_id})}.to_not raise_error
    end

    it 'should reflect changes upon reloading the private rtb' do
      expect{@rtb = @client.create_route_table({vpc_id: @vpc.vpc_id}).route_table}.to_not raise_error
      expect{@client.associate_route_table({route_table_id: @rtb.route_table_id, subnet_id: @subnet.subnet_id})}.to_not raise_error
      expect(@rtb.associations.empty?).to be true
      expect(@osaws.os_aws.reload_rtb(@rtb).associations.first.subnet_id).to eq(@subnet.subnet_id)
    end

    it 'should create and retrieve an existing private rtb' do
      expect{@rtb = @osaws.os_aws.find_or_create_private_rtb(@vpc, @subnet)}.to_not raise_error
      expect(@osaws.os_aws.retrieve_rtb(@subnet).route_table_id).to eq(@rtb.route_table_id)
    end

    it 'should find an already existing private rtb' do
      expect{@rtb = @osaws.os_aws.find_or_create_private_rtb(@vpc, @subnet)}.to_not raise_error
      @rtb_2 = @osaws.os_aws.find_or_create_private_rtb(@vpc, @subnet)
      expect(@rtb.route_table_id).to eq(@rtb_2.route_table_id)
    end

    it 'should self-heal if missing a route to the eigw in the private rtb' do
      expect{@rtb = @osaws.os_aws.find_or_create_private_rtb(@vpc, @subnet)}.to_not raise_error
      @client.delete_route({destination_ipv_6_cidr_block: "::/0", route_table_id: @rtb.route_table_id})
      @rtb = @osaws.os_aws.reload_rtb(@rtb)
      expect(@rtb.routes.select { |route| route.egress_only_internet_gateway_id == @eigw.egress_only_internet_gateway_id }.empty?).to be true
      expect{@rtb = @osaws.os_aws.find_or_create_private_rtb(@vpc, @subnet)}.to_not raise_error
      expect(@rtb.routes.select { |route| route.egress_only_internet_gateway_id == @eigw.egress_only_internet_gateway_id }.empty?).to be false
    end

    after :each do
      if @rtb
        @rtb = @osaws.os_aws.reload_rtb(@rtb)
        unless @rtb.associations.empty?
          @rtb.associations.each { |assoc| @client.disassociate_route_table({association_id: assoc.route_table_association_id})}
        end
        @client.delete_route_table({route_table_id: @rtb.route_table_id})
      end
      if @rtb_2
        if @rtb_2.route_table_id != @rtb.route_table_id
          @rtb_2 = @osaws.os_aws.reload_rtb(@rtb_2)
          unless @rtb_2.associations.empty?
            @rtb.associations.each { |assoc| @client.disassociate_route_table({association_id: assoc.route_table_association_id})}
          end
          @client.delete_route_table({route_table_id: @rtb_2.route_table_id})
        end
      end
    end

    after :all do
      @client.delete_egress_only_internet_gateway({egress_only_internet_gateway_id: @eigw.egress_only_internet_gateway_id})
      @client.delete_subnet({subnet_id: @subnet.subnet_id})
      sleep 2
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'public nacl methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      @vpc = @osaws.os_aws.find_or_create_vpc
      @subnet = @osaws.os_aws.find_or_create_public_subnet(@vpc)
      @igw = @osaws.os_aws.find_or_create_igw(@vpc)
      @default_nacl = @client.describe_network_acls({}).network_acls.select { |nacl| nacl.associations.map { |assoc| assoc.subnet_id }.include? @subnet.subnet_id }[0]
    end

    before :each do
      expect(@osaws.os_aws.retrieve_nacl(@subnet)).to be false
      @nacl = false
      @nacl_2 = false
    end

    it 'should create and re-associate a public nacl' do
      expect{@nacl = @client.create_network_acl({vpc_id: @vpc.vpc_id}).network_acl}.to_not raise_error
      expect{@osaws.os_aws.set_nacl(@subnet, @nacl)}.to_not raise_error
    end

    it 'should create and retrieve a new (non-default) public nacl' do
      expect{@nacl = @osaws.os_aws.find_or_create_public_nacl(@vpc, @subnet)}.to_not raise_error
      expect(@nacl.is_default).to eq false
      expect{@nacl_2 = @osaws.os_aws.find_or_create_public_nacl(@vpc, @subnet)}.to_not raise_error
      expect(@nacl_2.network_acl_id).to eq(@nacl.network_acl_id)
    end

    it 'should add routes to the public nacl enabling client and docker communications if not existing' do
      expect{@nacl = @osaws.os_aws.find_or_create_public_nacl(@vpc, @subnet)}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 100})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: false, network_acl_id: @nacl.network_acl_id, rule_number: 100})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 200})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: false, network_acl_id: @nacl.network_acl_id, rule_number: 200})}.to_not raise_error
      # Verify that the SSH and 2377 TCP rules are deleted
      @nacl = @osaws.os_aws.reload_nacl(@nacl)
      ingress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == false }.map { |rule| rule.rule_number }
      egress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == true }.map { |rule| rule.rule_number }
      expect(ingress_rule_numbers.include? 100).to be false
      expect(ingress_rule_numbers.include? 200).to be false
      expect(egress_rule_numbers.include? 100).to be false
      expect(egress_rule_numbers.include? 200).to be false
      # Verify that rules were recreated with rule numbers indexing from 400 by 10
      expect{@nacl = @osaws.os_aws.find_or_create_public_nacl(@vpc, @subnet)}.to_not raise_error
      entries = @nacl.entries.select { |entry| entry.protocol != '-1' }
      expectations = [
          {egress: true, ports: [1025, 65535], cidr: @osaws.os_aws.retrieve_visible_ip + '/32'},
          {egress: true, ports: [2377, 2377], cidr: '10.0.0.0/16'},
          {egress: false, ports: [22, 22], cidr: @osaws.os_aws.retrieve_visible_ip + '/32'},
          {egress: false, ports: [2377, 2377], cidr: '10.0.0.0/16'}
      ]
      expectations.each do |expectation|
        matching_rules = entries.select { |entry| (entry.cidr_block == expectation[:cidr]) &
            (entry.egress == expectation[:egress]) & (entry.port_range.from == expectation[:ports][0]) &
            (entry.port_range.to == expectation[:ports][1]) & (entry.protocol == '6')}
        expect(matching_rules.empty?).to be false
      end
    end

    it 'should not add public routes for 80, 443, and ephemeral port range if they have been altered' do
      expect{@nacl = @osaws.os_aws.find_or_create_public_nacl(@vpc, @subnet)}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 300})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: false, network_acl_id: @nacl.network_acl_id, rule_number: 300})}.to_not raise_error
      # Verify that the HTTP rules are deleted
      @nacl = @osaws.os_aws.reload_nacl(@nacl)
      ingress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == false }.map { |rule| rule.rule_number }
      egress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == true }.map { |rule| rule.rule_number }
      expect(ingress_rule_numbers.include? 300).to be false
      expect(egress_rule_numbers.include? 300).to be false
      # Verify that the HTTP rules were not re-created by the find_or_create_public_nacl method
      expect{@nacl = @osaws.os_aws.find_or_create_public_nacl(@vpc, @subnet)}.to_not raise_error
      entries = @nacl.entries.select { |entry| entry.protocol != '-1' }
      matching_rules = entries.select { |entry| (entry.port_range.to == 80) }
      expect(matching_rules.empty?).to be true
    end

    after :each do
      if @nacl
        @osaws.os_aws.set_nacl(@subnet, @default_nacl)
        @nacl = @osaws.os_aws.reload_nacl(@nacl)
        unless @nacl.associations.empty?
          raise "nacl #{@nacl.network_acl_id} is still associated with #{@nacl.associations[0].subnet_id}"
        end
        @client.delete_network_acl({network_acl_id: @nacl.network_acl_id})
      end
      if @nacl_2
        if @nacl_2.network_acl_id != @nacl.network_acl_id
          @nacl_2 = @osaws.os_aws.reload_nacl(@nacl_2)
          unless @nacl_2.associations.empty?
            raise "nacl #{@nacl_2.network_acl_id} is still associated with #{@nacl_2.associations[0].subnet_id}"
          end
          @client.delete_network_acl({network_acl_id: @nacl_2.network_acl_id})
        end
      end
    end

    after :all do
      @igw = @osaws.os_aws.reload_igw(@igw)
      @client.detach_internet_gateway({internet_gateway_id: @igw.internet_gateway_id, vpc_id: @vpc.vpc_id})
      @client.delete_internet_gateway({internet_gateway_id: @igw.internet_gateway_id})
      @client.delete_subnet({subnet_id: @subnet.subnet_id})
      sleep 2
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'private nacl methods' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
      @vpc = @osaws.os_aws.find_or_create_vpc
      @subnet = @osaws.os_aws.find_or_create_private_subnet(@vpc)
      @eigw = @osaws.os_aws.find_or_create_eigw(@vpc)
      @default_nacl = @client.describe_network_acls({}).network_acls.select { |nacl| nacl.associations.map { |assoc| assoc.subnet_id }.include? @subnet.subnet_id }[0]
    end

    before :each do
      expect(@osaws.os_aws.retrieve_nacl(@subnet)).to be false
      @nacl = false
      @nacl_2 = false
    end

    it 'should create and re-associate a private nacl' do
      expect{@nacl = @client.create_network_acl({vpc_id: @vpc.vpc_id}).network_acl}.to_not raise_error
      expect{@osaws.os_aws.set_nacl(@subnet, @nacl)}.to_not raise_error
    end

    it 'should create and retrieve a new (non-default) private nacl' do
      expect{@nacl = @osaws.os_aws.find_or_create_private_nacl(@vpc, @subnet)}.to_not raise_error
      expect(@nacl.is_default).to eq false
      expect{@nacl_2 = @osaws.os_aws.find_or_create_private_nacl(@vpc, @subnet)}.to_not raise_error
      expect(@nacl_2.network_acl_id).to eq(@nacl.network_acl_id)
    end

    it 'should add routes to the private nacl enabling client and docker communications if not existing' do
      expect{@nacl = @osaws.os_aws.find_or_create_private_nacl(@vpc, @subnet)}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 100})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: false, network_acl_id: @nacl.network_acl_id, rule_number: 100})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 200})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: false, network_acl_id: @nacl.network_acl_id, rule_number: 200})}.to_not raise_error
      # Verify that the SSH and 2377 TCP rules are deleted
      @nacl = @osaws.os_aws.reload_nacl(@nacl)
      ingress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == false }.map { |rule| rule.rule_number }
      egress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == true }.map { |rule| rule.rule_number }
      expect(ingress_rule_numbers.include? 100).to be false
      expect(ingress_rule_numbers.include? 200).to be false
      expect(egress_rule_numbers.include? 100).to be false
      expect(egress_rule_numbers.include? 200).to be false
      # Verify that rules were recreated with rule numbers indexing from 400 by 10
      expect{@nacl = @osaws.os_aws.find_or_create_private_nacl(@vpc, @subnet)}.to_not raise_error
      entries = @nacl.entries.select { |entry| entry.protocol != '-1' }
      expectations = [
          {egress: true, ports: [1025, 65535], cidr: '10.0.0.0/24'},
          {egress: true, ports: [2377, 2377], cidr: '10.0.0.0/23'},
          {egress: false, ports: [22, 22], cidr: '10.0.0.0/24'},
          {egress: false, ports: [2377, 2377], cidr: '10.0.0.0/23'}
      ]
      expectations.each do |expectation|
        matching_rules = entries.select { |entry| (entry.cidr_block == expectation[:cidr]) &
            (entry.egress == expectation[:egress]) & (entry.port_range.from == expectation[:ports][0]) &
            (entry.port_range.to == expectation[:ports][1]) & (entry.protocol == '6')}
        expect(matching_rules.empty?).to be false
      end
    end

    it 'should not add routes for IPV6 traffic if they have been altered' do
      expect{@nacl = @osaws.os_aws.find_or_create_private_nacl(@vpc, @subnet)}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 300})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: true, network_acl_id: @nacl.network_acl_id, rule_number: 310})}.to_not raise_error
      expect{@client.delete_network_acl_entry({egress: false, network_acl_id: @nacl.network_acl_id, rule_number: 300})}.to_not raise_error
      # Verify that the ::/0 IPV6 rules are deleted
      @nacl = @osaws.os_aws.reload_nacl(@nacl)
      ingress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == false }.map { |rule| rule.rule_number }
      egress_rule_numbers = @nacl.entries.select{ |rule| rule.egress == true }.map { |rule| rule.rule_number }
      expect(ingress_rule_numbers.include? 300).to be false
      expect(egress_rule_numbers.include? 300).to be false
      expect(egress_rule_numbers.include? 310).to be false
      # Verify that the eigw rules were not re-created by the find_or_create_private_nacl method
      expect{@nacl = @osaws.os_aws.find_or_create_private_nacl(@vpc, @subnet)}.to_not raise_error
      entries = @nacl.entries.select { |entry| entry.protocol != '-1' }
      matching_rules = entries.select { |entry| (entry.ipv_6_cidr_block == '::/0') }
      expect(matching_rules.empty?).to be true
    end

    after :each do
      if @nacl
        @osaws.os_aws.set_nacl(@subnet, @default_nacl)
        @nacl = @osaws.os_aws.reload_nacl(@nacl)
        unless @nacl.associations.empty?
          raise "nacl #{@nacl.network_acl_id} is still associated with #{@nacl.associations[0].subnet_id}"
        end
        @client.delete_network_acl({network_acl_id: @nacl.network_acl_id})
      end
      if @nacl_2
        if @nacl_2.network_acl_id != @nacl.network_acl_id
          @nacl_2 = @osaws.os_aws.reload_nacl(@nacl_2)
          unless @nacl_2.associations.empty?
            raise "nacl #{@nacl_2.network_acl_id} is still associated with #{@nacl_2.associations[0].subnet_id}"
          end
          @client.delete_network_acl({network_acl_id: @nacl_2.network_acl_id})
        end
      end
    end

    after :all do
      @client.delete_egress_only_internet_gateway({egress_only_internet_gateway_id: @eigw.egress_only_internet_gateway_id})
      @client.delete_subnet({subnet_id: @subnet.subnet_id})
      sleep 2
      @client.delete_vpc({vpc_id: @vpc.vpc_id})
    end
  end

  context 'vpc networking e2e test' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
      @client = @osaws.os_aws.instance_variable_get(:@aws)
    end

    it 'should create all infrastructure through find_or_create and remove cleanly with remove_networking' do
      expect{@vpc = @osaws.os_aws.find_or_create_vpc}.to_not raise_error
      expect{@public_subnet = @osaws.os_aws.find_or_create_public_subnet(@vpc)}.to_not raise_error
      expect{@private_subnet = @osaws.os_aws.find_or_create_private_subnet(@vpc)}.to_not raise_error
      expect{@osaws.os_aws.find_or_create_igw(@vpc)}.to_not raise_error
      expect{@osaws.os_aws.find_or_create_eigw(@vpc)}.to_not raise_error
      expect{@osaws.os_aws.find_or_create_public_rtb(@vpc, @public_subnet)}.to_not raise_error
      expect{@osaws.os_aws.find_or_create_private_rtb(@vpc, @private_subnet)}.to_not raise_error
      expect{@osaws.os_aws.find_or_create_public_nacl(@vpc, @public_subnet)}.to_not raise_error
      expect{@osaws.os_aws.find_or_create_private_nacl(@vpc, @private_subnet)}.to_not raise_error
      expect(@osaws.os_aws.remove_networking(@vpc)).to be true
    end
  end

  context 'main networking method' do
    before :all do
      @osaws = OpenStudio::Aws::Aws.new
    end

    it 'should create and re-instantiate a single network configuration' do
      expect{@vpc_id = @osaws.os_aws.find_or_create_networking}.to_not raise_error
      expect{@vpc_id_2 = @osaws.os_aws.find_or_create_networking(@vpc_id)}.to_not raise_error
      expect(@vpc_id).to eq(@vpc_id_2)
      expect{@vpc_id_3 = @osaws.os_aws.find_or_create_networking}.to_not raise_error
      expect(@vpc_id).to eq(@vpc_id_3)
    end

    after :all do
      vpc = @osaws.os_aws.find_or_create_vpc
      @osaws.os_aws.remove_networking(vpc)
    end
  end
end
