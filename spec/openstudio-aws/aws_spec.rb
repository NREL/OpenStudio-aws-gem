require 'spec_helper'

describe OpenStudio::Aws::Aws do
  context 'ami lists' do
    it 'should allow a different region' do
      options = {
        region: 'sa-east-1',
        credentials: {
          access_key_id: 'some_random_access_key_id',
          secret_access_key: 'some_super_secret_access_key'
        }
      }
      aws = OpenStudio::Aws::Aws.new(options)
    end

    it 'should allow a different region' do
      options = {
        ami_lookup_version: 2,
        credentials: {
          access_key_id: 'some_random_access_key_id',
          secret_access_key: 'some_super_secret_access_key'
        }
      }
      aws = OpenStudio::Aws::Aws.new(options)

      expect(aws.default_amis).not_to be_nil
    end
  end

  context 'should error' do
    it 'should not find a json' do
      options = {
        ami_lookup_version: 2,
        url: '/unknown/url'
      }
      expect { aws = OpenStudio::Aws::Aws.new(options) }.to raise_exception
    end
  end

  context 'version testing' do
    it 'version 2: should find the right AMIs Server 1.21.15' do
      options = {
        ami_lookup_version: 2,
        openstudio_server_version: '1.21.15'
      }
      aws = OpenStudio::Aws::Aws.new(options)
      expect(aws.default_amis[:worker]).to eq('ami-ccb35ada')
      expect(aws.default_amis[:server]).to eq('ami-54b45d42')
    end
  end

  context 'custom keys' do
    it 'should error on key not found' do
      options = {
        aws_key_pair_name: 'a_random_key_pair',
        private_key_file_name: '/file/should/not/exist', # required if using an existing "aws_key_pair_name"
      }
      aws = OpenStudio::Aws::Aws.new

      expect { aws.create_server(options) }.to raise_error(/Private key was not found.*/)
    end

    it 'should require a private key' do
      options = {
        aws_key_pair_name: 'a_random_key_pair',
        private_key_file_name: nil, # required if using an existing "aws_key_pair_name"
      }
      aws = OpenStudio::Aws::Aws.new

      expect { aws.create_server(options) }.to raise_error /Must pass in the private_key_file_name/
    end

    it 'should create a key in another directory' do
      options = {}
      aws = OpenStudio::Aws::Aws.new
      expect(aws.save_directory).to eq File.expand_path('.')

      options = {
        save_directory: 'spec/output/save_path'
      }
      aws = OpenStudio::Aws::Aws.new(options)
      expect(aws.save_directory).to eq File.join(File.expand_path('.'), 'spec/output/save_path')
    end
  end

  context 'proxy configuration' do
    it 'should create an instance' do
      options = {
        credentials: {
          access_key_id: 'some_random_access_key_id',
          secret_access_key: 'some_super_secret_access_key'
        }
      }

      @aws = OpenStudio::Aws::Aws.new(options)
      expect(@aws.os_aws).not_to be_nil
    end

    it 'should create a AWS instance with a proxy' do
      options = {
        credentials: {
          access_key_id: 'some_random_access_key_id',
          secret_access_key: 'some_super_secret_access_key'
        },
        proxy: {
          host: '192.168.0.1',
          port: 8080
        }
      }
      @aws = OpenStudio::Aws::Aws.new(options)
      expect(@aws.os_aws.proxy).to eq(options[:proxy])
    end

    it 'should create a AWS instance with a proxy with username / password' do
      options = {
        credentials: {
          access_key_id: 'some_random_access_key_id',
          secret_access_key: 'some_super_secret_access_key'
        },
        proxy: {
          host: '192.168.0.1',
          port: 8080,
          username: 'username',
          password: 'password'
        }
      }

      @aws = OpenStudio::Aws::Aws.new(options)
      expect(@aws.os_aws.proxy).to eq(options[:proxy])
    end
  end

  context 'availability zones' do
    it 'should describe the availability zones' do
      options = {}
      aws = OpenStudio::Aws::Aws.new(options)
      az = aws.describe_availability_zones

      expect(az[:availability_zone_info]).to be_an Array
      expect(az[:availability_zone_info].first[:zone_name]).to eq 'us-east-1a'
    end
  end

  context 'total instances' do
    it 'should describe the total instances' do
      options = {}
      aws = OpenStudio::Aws::Aws.new(options)
      az = aws.total_instances_count

      expect(az[:total_instances]).to_not be_nil
      expect(az[:region]).to_not be_nil
    end
  end
end
