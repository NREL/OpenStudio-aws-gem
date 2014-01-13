require 'spec_helper'

describe OpenStudio::Aws::Aws do
  context "create a new instance" do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new
    end

    it "should create a new instance" do
      @aws.should_not be_nil
    end

    it "should ask the user to create a new config file" do
    end

    it "should create a server" do
      # use the default instance type
      options = {instance_type: "t1.micro", image_id: "ami-fb301292"}

      #options = {instance_type: "m1.small" }
      @aws.create_server(options)
      expect(@aws.os_aws.server).not_to be_nil
    end

    it "should create a 1 worker" do
      options = {instance_type: "t1.micro", image_id: "ami-21301248"}
      #options = {instance_type: "m1.small" }
      #server_json[:instance_type] = "m2.4xlarge"
      #server_json[:instance_type] = "m2.2xlarge"
      #server_json[:instance_type] = "t1.micro"

      @aws.create_workers(1, options)

      expect(@aws.os_aws.workers).to have(1).thing
      expect(@aws.os_aws.workers[0].data[:dns]).not_to be_nil
    end
    
    it "should be able to connect a worker to an existing server" do
      options = {instance_type: "t1.micro", image_id: "ami-a9e4ccc0"}

      # will require a new @aws class--but attached to same group_uuid
      @config = OpenStudio::Aws::Config.new
      @aws_2 = OpenStudio::Aws::Aws.new
                                       
      @aws_2.os_aws.find_server(@aws.os_aws.group_uuid)

      expect(@aws.os_aws.server).not_to be_nil
    end

    it "should kill running instances" do
      # how to test this?
    end
  end

  context "workers before server" do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it "should not create any workers" do
      expect { @aws.create_workers(5) }.to raise_error
    end
  end

  context "larger cluster" do

  end

end
