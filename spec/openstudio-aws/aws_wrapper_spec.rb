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
end
