# This class is a wrapper around the command line version that is in the OpenStudio repository.


module OpenStudio
  module Aws
    class Aws
      attr_reader :server_data

      def initialize()
        # read in the config.yml file to get the secret/private key
        @config = OpenStudio::Aws::Config.new()
        @server_data = nil
      end

      # command line call to create a new instance.  This should be more tightly integrated with teh os-aws.rb gem
      def create_server(instance_data = {})
        # TODO: find a way to override the instance ids here in case we want to prototype
        defaults = {instance_type: "m2.xlarge"}
        instance_data = defaults.merge(instance_data)

        # Since this is a command line call then make sure to escape the quotes in the JSON
        instance_string = instance_data.to_json.gsub("\"", "\\\\\"")

        # Get the location of the os-aws.rb file.  Use the relative path from where this file exists
        os_aws_file = File.expand_path(File.join(File.dirname(__FILE__), "..", "lib", "os-aws.rb"))
        raise "os_aws_file does not exist where it is expected: #{os_aws_file}" unless File.exists?(os_aws_file)

        # Call the openstudio script to start the ec2 instance 
        start_string = "ruby #{os_aws_file} #{@config.access_key} #{@config.secret_key} us-east-1 EC2 launch_server \"#{instance_string}\""
        puts "#{start_string}"
        server_data_str = `#{start_string}`          #{:no_data => true}.to_json #
        @server_data = JSON.parse(server_data_str, :symbolize_names => true)

        # Save pieces of the data for passing to the worker node
        server_key_file = "ec2_server_key.pem"
        File.open(server_key_file, "w") { |f| f << @server_data[:private_key] }
        File.chmod(0600, server_key_file)

        # Save off the server data to be loaded into the worker nodes.  The Private key needs to e read from a
        # file in the worker node, so save that name instead in the HASH along with a couple other changes
        @server_data[:private_key] = server_key_file
        if @server_data[:server]
          @server_data[:server_id] = @server_data[:server][:id]
          @server_data[:server_ip] = @server_data[:server][:ip]
          @server_data[:server_dns] = @server_data[:server][:dns]
        end

        File.open("server_data.json", "w") { |f| f << JSON.pretty_generate(@server_data) }

        # Print out some debugging commands (probably work on mac/linux only)
        puts ""
        puts "Server SSH Command:"

        puts "ssh -i #{server_key_file} ubuntu@#{@server_data[:server_dns]}"
      end

      def create_workers(number_of_instances, instance_data = {})
        raise "Can't create workers without a server instance running" if @server_data.nil?
      end

    end
  end
end
