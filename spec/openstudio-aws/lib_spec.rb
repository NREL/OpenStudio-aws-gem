require 'spec_helper'

describe OpenStudioAwsWrapper do
  context "unauthenticated session" do
    it "should fail to authenticate" do
      credentials = {:access_key_id => "blah", :secret_access_key => "key", :region => "us-east-1", :ssl_verify_peer => false}
      @os_aws = OpenStudioAwsWrapper.new(credentials)
      expect { @os_aws.describe_availability_zones }.to raise_exception
    end
  end

  context "authenticated session" do
    before :all do
      config = OpenStudio::Aws::Config.new

      credentials = {:access_key_id => config.access_key, :secret_access_key => config.secret_key, :region => "us-east-1", :ssl_verify_peer => false}
      @os_aws = OpenStudioAwsWrapper.new(credentials)
    end

    context "new instance" do
      it "should be created" do
        expect { @os_aws }.not_to be_nil
      end
    end

    context "availability" do
      it "should describe the zones" do
        resp = @os_aws.describe_availability_zones
        expect { resp }.not_to be_nil
        resp[:availability_zone_info].length.should eq(4)
                             
        resp[:availability_zone_info].inspect.should eq("[{:zone_name=>\"us-east-1a\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1b\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1c\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1d\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}]")
        
        resp = @os_aws.describe_availability_zones_json
        expect { resp }.not_to be_nil

      end
      
      it "should list number of instances" do
        resp = @os_aws.describe_total_instances
        expect { resp }.not_to be_nil
      end
    end
    
  end


end
