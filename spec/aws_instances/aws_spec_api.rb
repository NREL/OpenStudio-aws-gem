require 'spec_helper'

describe OpenStudio::Aws::Aws do
  context 'create a new instance' do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new

      @group_id = nil
    end

    it 'should create a new instance' do
      @aws.should_not be_nil
    end

    it 'should create a server' do
      options = {instance_type: 'm1.small', image_id: 'ami-29faca40'}

      test_pem_file = "ec2_server_key.pem"
      FileUtils.rm_f test_pem_file if File.exist? test_pem_file
      FileUtils.rm_f 'server_data.json' if File.exist? 'server_data.json'

      @aws.create_server(options)

      expect(File.exist?('ec2_server_key.pem')).to be true
      expect(File.exist?('server_data.json')).to be true
      expect(@aws.os_aws.server).not_to be_nil

      h = @os_aws.server.to_os_hash
      expect(h[:group_id]).to be_a String
      expect(h[:group_id]).to match /^\d{10}$/
      expect(h[:location]).to be 'AWS'

      @group_id = h[:group_id]


    end

    it 'should create a 1 worker' do
      options = {instance_type: 'm1.small', image_id: 'ami-95f9c9fc'}

      @aws.create_workers(1, options)

      expect(@aws.os_aws.workers).to have(1).thing
      expect(@aws.os_aws.workers[0].data[:dns]).not_to be_nil
    end

    it 'should be able to connect a worker to an existing server' do
      options = {instance_type: 'm1.small', image_id: 'ami-29faca40'}

      # will require a new @aws class--but attached to same group_uuid
      @config = OpenStudio::Aws::Config.new
      @aws_2 = OpenStudio::Aws::Aws.new

      @aws_2.os_aws.find_server(@aws.os_aws.group_uuid)

      expect(@aws.os_aws.server).not_to be_nil
    end

    it 'should kill running instances' do
      # how to test this?
    end

    after :all do
      FileUtils.rm_f 'ec2_server_key.pem' if File.exist? 'ec2_server_key.pem'
    end
  end

  context 'upload data to a server' do
    it 'should create a server' do
      config = OpenStudio::Aws::Config.new
      aws = OpenStudio::Aws::Aws.new

      options = {instance_type: 'm1.small', image_id: 'ami-29faca40'}

      aws.create_server(options)


    end

    it 'should upload a file after loading the existing server' do
      expect(File.exist?('server_data.json')).to be true

      j = JSON.parse(File.read('server_data.json'), symbolize_names: true)

      config = OpenStudio::Aws::Config.new
      aws = OpenStudio::Aws::Aws.new

      aws.load_instance_info_from_file('server_data.json')

      expect(aws.os_aws.server.group_uuid).to eq j[:group_id]
      puts aws.os_aws.server.inspect

      local_file = File.expand_path('../resources/upload_me.sh', File.dirname(__FILE__))
      remote_file = '/mnt/openstudio/i_uploaded_this_file.sh'

      aws.upload_file(:server, local_file, remote_file)
    end

    after :all do
      #FileUtils.rm_f 'ec2_server_key.pem' if File.exist? 'ec2_server_key.pem'
    end
  end

  context 'workers before server' do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should not create any workers' do
      expect { @aws.create_workers(5) }.to raise_error
    end
  end

  # context 'create ebs storage' do
  #   before(:all) do
  #     @aws = OpenStudio::Aws::Aws.new
  #   end
  #
  #   it 'should create an EBS volume' do
  #     options = {instance_type: 'm1.small', image_id: 'ami-29faca40', ebs_volume_size: 128}
  #     @aws.create_volume()
  #     @aws.create_server(options)
  #     expect(@aws.os_aws.server).not_to be_nil
  #   end
  #
  # end

end
