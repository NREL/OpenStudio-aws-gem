require 'spec_helper'

describe OpenStudioAwsWrapper do
  context "unauthenticated session" do
    it "should fail to authenticate" do
      options = {
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
                  :region => "us-east-1",
                  :ssl_verify_peer => false
              }
      }

      @os_aws = OpenStudioAwsWrapper.new(options)
      expect { @os_aws.describe_availability_zones }.to raise_exception
    end
  end

  context "authenticated session" do
    before :all do
      @aws = OpenStudio::Aws::Aws.new
    end

    context "new instance" do
      it "should be created" do
        expect { @aws.os_aws }.not_to be_nil
      end
    end

    context "availability" do
      it "should describe the zones" do
        resp = @aws.os_aws.describe_availability_zones
        expect { resp }.not_to be_nil
        resp[:availability_zone_info].length.should eq(4)

        resp[:availability_zone_info].inspect.should eq("[{:zone_name=>\"us-east-1a\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1b\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1c\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}, {:zone_name=>\"us-east-1d\", :state=>\"available\", :region_name=>\"us-east-1\", :messages=>[]}]")

        resp = @aws.os_aws.describe_availability_zones_json
        expect { resp }.not_to be_nil

      end

      it "should list number of instances" do
        resp = @aws.os_aws.describe_total_instances
        expect { resp }.not_to be_nil
      end
    end

    context "create new ami json" do
      it "should describe existing AMIs" do
        resp = @aws.os_aws.describe_amis(nil, nil, true)
        expect(resp).not_to be_nil
      end

      it "should create a new json" do
        resp = @aws.os_aws.create_new_ami_json(1)
      end

    end
  end


end
