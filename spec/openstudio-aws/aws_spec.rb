require 'spec_helper'

describe OpenStudio::Aws::Aws do
  context "proxy configuration" do
    before :all do

    end
    
    it "should create an instance" do
      options = {
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
                  :region => "us-east-1",
                  :ssl_verify_peer => false
              }
          }
      
      @aws = OpenStudio::Aws::Aws.new(options)
      expect(@aws.os_aws).not_to be_nil
    end

    it "should create a AWS instance with a proxy" do
      options = {
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
                  :region => "us-east-1",
                  :ssl_verify_peer => false
              },
          :proxy => {
              :host => "192.168.0.1",
              :port => 8080
          }
      }
      @aws = OpenStudio::Aws::Aws.new(options)
      expect(@aws.os_aws.proxy).to eq(options[:proxy])
    end

    it "should create a AWS instance with a proxy with username / password" do
      options = {
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
                  :region => "us-east-1",
                  :ssl_verify_peer => false
              },
          :proxy => {
              :host => "192.168.0.1",
              :port => 8080,
              :username => "username",
              :password => "password"
          }
      }

      @aws = OpenStudio::Aws::Aws.new(options)
      expect(@aws.os_aws.proxy).to eq(options[:proxy])

    end
  end
end
