require 'spec_helper'

describe OpenStudio::Aws::Aws do
  context 'create a new instance' do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should create a new instance' do
      @aws.should_not be_nil
    end

    it 'should create a server' do
      # use the default instance type
      options = {instance_type: 'm1.small', image_id: 'ami-29faca40'}

      @aws.create_server(options)
      expect(@aws.os_aws.server).not_to be_nil
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
  end

  context 'workers before server' do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should not create any workers' do
      expect { @aws.create_workers(5) }.to raise_error
    end
  end

  context 'create ebs storage' do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should create an EBS volume' do
      options = {instance_type: 'm1.small', image_id: 'ami-29faca40', ebs_volume_size: 128}
      @aws.create_volume()
      @aws.create_server(options)
      expect(@aws.os_aws.server).not_to be_nil
    end

  end

end
