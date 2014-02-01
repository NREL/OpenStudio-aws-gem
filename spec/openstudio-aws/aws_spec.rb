require 'spec_helper'

describe OpenStudio::Aws::Aws do
  context "ami lists" do
    it "should allow a different region" do
      options = {
          :region => "sa-east-1",
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
              }
      }
      aws = OpenStudio::Aws::Aws.new(options)
    end

    it "should allow a different region" do
      options = {
          :ami_lookup_version => 2
      }
      aws = OpenStudio::Aws::Aws.new(options)
      puts aws.default_amis
    end
  end

  context "should error" do
    it "should not find a json" do
      options = {
          :ami_lookup_version => 2,
          :url => 'unknown/url'
      }
      expect{ OpenStudio::Aws::Aws.new(options) }.to raise_exception
    end

  end

  context "proxy configuration" do
    it "should create an instance" do
      options = {
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
              }
      }

      @aws = OpenStudio::Aws::Aws.new(options)
      puts @aws.inspect
      expect(@aws.os_aws).not_to be_nil
    end

    it "should create a AWS instance with a proxy" do
      options = {
          :credentials =>
              {
                  :access_key_id => "some_random_access_key_id",
                  :secret_access_key => "some_super_secret_access_key",
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
