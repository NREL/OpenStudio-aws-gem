require 'spec_helper'

describe OpenStudio::Aws::Config do
  context 'create a new config' do
    it 'should create a new instance' do
      @config = OpenStudio::Aws::Config.new
      expect(@config).not_to be_nil
    end

    it 'should create a new file' do
      local_file = 'test.config'
      File.delete local_file if File.exist? local_file

      expect { OpenStudio::Aws::Config.new local_file }.to raise_error /Config file not found. A template has been added, please edit and save: test.config/
      expect(File.exist?(local_file)).to eq true

      # read the file and make sure that the template is there
      config = YAML.load(File.read(local_file))
      expect(config[:access_key_id]).to eq 'YOUR_ACCESS_KEY_ID'
      expect(config[:secret_access_key]).to eq 'YOUR_SECRET_ACCESS_KEY'
    end

    it 'should read old format' do
      # make sure that we can read the old format which has non-symoblized keys
      local_file = 'test_custom_old.config'

      data = {
        'access_key_id' =>  'abcd',
        'secret_access_key' => 'efgh'
      }

      File.open(local_file, 'w') { |f| f << data.to_yaml }
      config = OpenStudio::Aws::Config.new local_file
      expect(config.access_key).to eq 'abcd'
      expect(config.secret_key).to eq 'efgh'
    end

    it 'should read a custom file' do
      local_file = 'test_custom.config'

      # create the file
      data = {
        access_key_id: 'random_key',
        secret_access_key: 'random_secret_key'
      }

      File.open(local_file, 'w') { |f| f << data.to_yaml }

      config = OpenStudio::Aws::Config.new local_file
      expect(config.access_key).to eq 'random_key'
      expect(config.secret_key).to eq 'random_secret_key'
    end
  end
end
