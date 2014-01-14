# This class is a wrapper around the command line version that is in the OpenStudio repository.
module OpenStudio
  module Aws
    class Aws
      attr_reader :os_aws

      def initialize()
        # read in the config.yml file to get the secret/private key
        @config = OpenStudio::Aws::Config.new()

        config = {:access_key_id => @config.access_key, :secret_access_key => @config.secret_key, :region => "us-east-1", :ssl_verify_peer => false}
        @os_aws = OpenStudioAwsWrapper.new(config)
        @local_key_file_name = nil

        # this will grab the default version of openstudio ami versions
        @default_amis = OpenStudioAmis.new(1).get_amis
      end

      # command line call to create a new instance.  This should be more tightly integrated with teh os-aws.rb gem
      def create_server(instance_data = {})
        defaults = {instance_type: "m2.xlarge", image_id: @default_amis['server']}
        instance_data = defaults.merge(instance_data)

        @os_aws.create_or_retrieve_security_group("openstudio-worker-sg-v1")
        @os_aws.create_or_retrieve_key_pair

        @local_key_file_name = "ec2_server_key.pem"
        @os_aws.save_private_key(@local_key_file_name)
        @os_aws.launch_server(instance_data[:image_id], instance_data[:instance_type])

        puts @os_aws.server.to_os_hash.to_json

        # Call the openstudio script to start the ec2 instance 
        #start_string = "ruby #{os_aws_file_location} #{@config.access_key} #{@config.secret_key} us-east-1 EC2 launch_server \"#{instance_string}\""
        #puts "Server Command: #{start_string}"
        #server_data_str = `#{start_string}`
        #@server_data = JSON.parse(server_data_str, :symbolize_names => true)

        # Save pieces of the data for passing to the worker node

        #File.open(server_key_file, "w") { |f| f << @server_data[:private_key] }
        #File.chmod(0600, server_key_file)

        # Save off the server data to be loaded into the worker nodes.  The Private key needs to e read from a
        # file in the worker node, so save that name instead in the HASH along with a couple other changes
        #@server_data[:private_key] = server_key_file
        #if @server_data[:server]
        #  @server_data[:server_id] = @server_data[:server][:id]
        #  @server_data[:server_ip] = @server_data[:server][:ip]
        #  @server_data[:server_dns] = @server_data[:server][:dns]
        #end

        File.open("server_data.json", "w") { |f| f << JSON.pretty_generate(@os_aws.server.to_os_hash) }

        # Print out some debugging commands (probably work on mac/linux only)
        puts ""
        puts "Server SSH Command:"

        puts "ssh -i #{@local_key_file_name} ubuntu@#{@os_aws.server.data[:dns]}"
      end

      def create_workers(number_of_instances, instance_data = {})
        defaults = {instance_type: "m2.4xlarge", image_id: @default_amis['worker']}
        instance_data = defaults.merge(instance_data)


        #todo: raise an exception if the instance type and image id don't match
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
