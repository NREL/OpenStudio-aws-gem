require 'spec_helper'

describe OpenStudio::Aws do


  context "create a new instance" do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it "should create a new instance" do
      @aws.should_not be_nil
    end

    it "should ask the user to create a new config file" do
    end

    it "should create a server" do
      # use the default instance type
      @aws.create_server()
      @aws.server_data[:server_dns].should_not be_nil
    end
    
    it "should create a 1 worker" do
      
    end


  end

  context "workers before server" do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it "should not create any workers" do
      expect {@aws.create_workers(5)}.to raise_error
    end

  end

end
