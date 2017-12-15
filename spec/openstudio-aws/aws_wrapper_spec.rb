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
      expect(@osaws.os_aws.retrieve_igw('oss-vpc-v0.1-igw-v0.1', @vpc)).to be false
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

  end

  context 'private rtb methods' do

  end

end
