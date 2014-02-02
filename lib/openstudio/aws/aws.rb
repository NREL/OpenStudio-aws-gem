# This class is a wrapper around the command line version that is in the OpenStudio repository.
module OpenStudio
  module Aws
    VALID_OPTIONS = [
        :proxy, :credentials, :ami_lookup_version, :openstudio_server_version,
        :region, :ssl_verify_peer, :host, :url
    ]

    class Aws
      attr_reader :os_aws
      attr_reader :default_amis

      # default constructor to create the AWS class that can spin up server and worker instances.
      # options are optional with the following support:
      #   credentials => {:access_key_id, :secret_access_key, :region, :ssl_verify_peer}
      #   proxy => {:host => "192.168.0.1", :port => "8808", :username => "user", :password => "password"}}
      def initialize(options = {})
        invalid_options = options.keys - VALID_OPTIONS
        if invalid_options.any?
          raise ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
        end

        # merge in some defaults
        defaults = {
            :ami_lookup_version => 1,
            :region => 'us-east-1',
            :ssl_verify_peer => false,
            :host => 'developer.nrel.gov',
            :url => '/downloads/buildings/openstudio/server'
        }
        options = defaults.merge(options)


        # read in the config.yml file to get the secret/private key
        if !options[:credentials]
          config_file = OpenStudio::Aws::Config.new()

          # populate the credentials
          options[:credentials] =
              {
                  :access_key_id => config_file.access_key,
                  :secret_access_key => config_file.secret_key,
                  :region => options[:region],
                  :ssl_verify_peer => options[:ssl_verify_peer]
              }
        else
          options[:credentials][:region] = options[:region]
          options[:credentials][:ssl_verify_peer] = options[:ssl_verify_peer]
        end

        if options[:proxy]
          proxy_uri = nil
          if options[:proxy][:username]
            proxy_uri = "https://#{options[:proxy][:username]}:#{options[:proxy][:password]}@#{options[:proxy][:host]}:#{options[:proxy][:port]}"
          else
            proxy_uri = "https://#{options[:proxy][:host]}:#{options[:proxy][:port]}"
          end
          # todo: remove this proxy_uri and make a method to format correctly
          options[:proxy_uri] = proxy_uri

          #todo: do we need to escape a couple of the argument of username and password

          #todo: set some environment variables for system based proxy
        end

        #puts "Final options are: #{options.inspect}"

        @os_aws = OpenStudioAwsWrapper.new(options)
        @local_key_file_name = nil

        # this will grab the default version of openstudio ami versions
        # get the arugments for the AMI lookup
        ami_options = {}
        ami_options[:openstudio_server_version] = options[:openstudio_server_version] if options[:openstudio_server_version]
        ami_options[:host] = options[:host] if options[:host]
        ami_options[:url] = options[:url] if options[:url]
        
        @default_amis = OpenStudioAmis.new(options[:ami_lookup_version], ami_options).get_amis
      end

      # command line call to create a new instance.  This should be more tightly integrated with teh os-aws.rb gem
      def create_server(instance_data = {}, server_json_filename = "server_data.json")
        defaults = {instance_type: "m2.xlarge", image_id: @default_amis['server']}
        instance_data = defaults.merge(instance_data)

        @os_aws.create_or_retrieve_security_group("openstudio-worker-sg-v1")
        @os_aws.create_or_retrieve_key_pair

        @local_key_file_name = "ec2_server_key.pem"
        @os_aws.save_private_key(@local_key_file_name)
        @os_aws.launch_server(instance_data[:image_id], instance_data[:instance_type])

        puts @os_aws.server.to_os_hash.to_json

        File.open(server_json_filename, "w") { |f| f << JSON.pretty_generate(@os_aws.server.to_os_hash) }

        # Print out some debugging commands (probably work on mac/linux only)
        puts ""
        puts "Server SSH Command:"

        puts "ssh -i #{@local_key_file_name} ubuntu@#{@os_aws.server.data[:dns]}"
      end

      def create_workers(number_of_instances, instance_data = {})
        defaults = {instance_type: "m2.4xlarge"}
        instance_data = defaults.merge(instance_data)

        if instance_data[:image_id].nil?
          if instance_data[:instance_type] =~ /cc2|c3/
            instance_data[:image_id] = @default_amis['cc2worker']
          else
            instance_data[:image_id] = @default_amis['worker']
          end
        end

        raise "Can't create workers without a server instance running" if @os_aws.server.nil?

        @os_aws.launch_workers(instance_data[:image_id], instance_data[:instance_type], number_of_instances)

        ## append the information to the server_data hash that already exists
        #@server_data[:instance_type] = instance_data[:instance_type]
        #@server_data[:num] = number_of_instances
        #server_string = @server_data.to_json.gsub("\"", "\\\\\"")
        #
        #start_string = "ruby #{os_aws_file_location} #{@config.access_key} #{@config.secret_key} us-east-1 EC2 launch_workers \"#{server_string}\""
        #puts "Worker Command: #{start_string}"
        #worker_data_string = `#{start_string}`
        #@worker_data = JSON.parse(worker_data_string, :symbolize_names => true)
        #File.open("worker_data.json", "w") { |f| f << JSON.pretty_generate(worker_data) }
        #
        ## Print out some debugging commands (probably work on mac/linux only)
        puts ""
        puts "Worker SSH Command:"
        @os_aws.workers.each do |worker|
          puts "ssh -i #{@local_key_file_name} ubuntu@#{worker.data[:dns]}"
        end

        puts ""
        puts "Waiting for server/worker configurations"

        @os_aws.configure_server_and_workers
      end

      def kill_instances()
        # Add this method to kill all the running instances
      end

      private

      def os_aws_file_location
        # Get the location of the os-aws.rb file.  Use the relative path from where this file exists
        os_aws_file = File.expand_path(File.join(File.dirname(__FILE__), "..", "lib", "os-aws.rb"))
        raise "os_aws_file does not exist where it is expected: #{os_aws_file}" unless File.exists?(os_aws_file)

        os_aws_file
      end

    end
  end
end
