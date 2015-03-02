# This class is a wrapper around the command line version that is in the OpenStudio repository.
module OpenStudio
  module Aws
    VALID_OPTIONS = [
      :proxy, :credentials, :ami_lookup_version, :openstudio_version,
      :openstudio_server_version, :region, :ssl_verify_peer, :host, :url
    ]

    class Aws
      # Deprecate OS_AWS object
      attr_reader :os_aws
      attr_reader :default_amis

      # default constructor to create the AWS class that can spin up server and worker instances.
      # options are optional with the following support:
      #   credentials => {:access_key_id, :secret_access_key, :region, :ssl_verify_peer}
      #   proxy => {:host => "192.168.0.1", :port => "8808", :username => "user", :password => "password"}}
      def initialize(options = {})
        invalid_options = options.keys - VALID_OPTIONS
        if invalid_options.any?
          fail ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
        end

        # merge in some defaults
        defaults = {
          ami_lookup_version: 1,
          region: 'us-east-1',
          ssl_verify_peer: false,
          host: 'developer.nrel.gov',
          url: '/downloads/buildings/openstudio/api'
        }
        options = defaults.merge(options)

        # read in the config.yml file to get the secret/private key
        if !options[:credentials]
          config_file = OpenStudio::Aws::Config.new

          # populate the credentials
          options[:credentials] =
              {
                access_key_id: config_file.access_key,
                secret_access_key: config_file.secret_key,
                region: options[:region],
                ssl_verify_peer: options[:ssl_verify_peer]
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

          # todo: do we need to escape a couple of the argument of username and password

          # todo: set some environment variables for system based proxy
        end

        # puts "Final options are: #{options.inspect}"

        @os_aws = OpenStudioAwsWrapper.new(options)

        @instances_json = nil

        # this will grab the default version of openstudio ami versions
        # get the arugments for the AMI lookup
        ami_options = {}
        ami_options[:openstudio_server_version] = options[:openstudio_server_version] if options[:openstudio_server_version]
        ami_options[:openstudio_version] = options[:openstudio_version] if options[:openstudio_version]
        ami_options[:host] = options[:host] if options[:host]
        ami_options[:url] = options[:url] if options[:url]

        @default_amis = OpenStudioAmis.new(options[:ami_lookup_version], ami_options).get_amis
      end

      # def load_data_from_json(json_filename)
      #   @os_aws.load_data_from_json
      #
      #
      # end

      # command line call to create a new instance.  This should be more tightly integrated with teh os-aws.rb gem
      def create_server(options = {}, instances_json = 'server_data.json')
        defaults = {
          instance_type: 'm2.xlarge',
          security_groups: [],
          image_id: @default_amis[:server],
          user_id: 'unknown_user',

          # optional -- will default later
          associate_public_ip_address: nil,
          subnet_id: nil,
          ebs_volume_id: nil,
          aws_key_pair_name: nil,
          private_key_file_name: nil, # required if using an existing "aws_key_pair_name"
          tags: []
        }
        options = defaults.merge(options)

        # for backwards compatibilty, still allow security_group
        if options[:security_group]
          warn "Pass security_groups as an array instead of security_group. security_group will be deprecated in 0.4.0"
          options[:security_groups] = [ options[:security_group] ]
        end

        if options[:aws_key_pair_name]
          fail 'Must pass in the private_key_file_name' unless options[:private_key_file_name]
          fail "Private key was not found: #{options[:private_key_file_name]}" unless File.exist? options[:private_key_file_name]
        end

        if options[:security_groups].empty?
          # if the user has not specified any security groups, then create one called: 'openstudio-server-sg-v1'
          @os_aws.create_or_retrieve_default_security_group
        else
          @os_aws.security_groups = options[:security_groups]
        end

        @os_aws.create_or_retrieve_key_pair options[:aws_key_pair_name]

        # If using an already_existing key_pair, then you must pass in the private key file name
        if options[:aws_key_pair_name]
          @os_aws.load_private_key options[:private_key_file_name]
          @os_aws.private_key_file_name = options[:private_key_file_name]
        else
          # Save the private key if you did not pass in an already existing key_pair_name
          @os_aws.save_private_key('ec2_server_key.pem')
        end

        server_options = {
            user_id: options[:user_id],
            tags: options[:tags],
            subnet_id: options[:subnet_id],
            associate_public_ip_address: options[:associate_public_ip_address]
        }

        # if instance_data[:ebs_volume_id]
        #   server_options[:ebs_volume_id] = instance_data[:ebs_volume_id]
        # end

        @os_aws.launch_server(options[:image_id], options[:instance_type], server_options)

        @instances_json = instances_json
        save_cluster_json(@instances_json)



        # Print out some debugging commands (probably work on mac/linux only)
        puts ''
        puts 'Server SSH Command:'

        puts "ssh -i #{@os_aws.private_key_file_name} ubuntu@#{@os_aws.server.data[:dns]}"
      end

      def create_workers(number_of_instances, options = {}, user_id = 'unknown_user')
        defaults = {
          instance_type: 'm2.4xlarge',
          security_groups: [],
          image_id: nil, # don't prescribe the image id so that it can determine later
          user_id: user_id,

          # optional -- will default later
          associate_public_ip_address: nil,
          subnet_id: nil,
          ebs_volume_id: nil,
          aws_key_pair_name: nil,
          private_key_file_name: nil, # required if using an existing "aws_key_pair_name",
          tags: []
        }
        options = defaults.merge(options)

        # for backwards compatibilty, still allow security_group
        if options[:security_group]
          warn "Pass security_groups as an array instead of security_group. security_group will be deprecated in 0.4.0"
          options[:security_groups] = [ options[:security_group] ]
        end


        # Get the right worker AMI ids based on the type of instance
        if options[:image_id].nil?
          options[:image_id] = determine_image_type(options[:instance_type])
        end

        fail "Can't create workers without a server instance running" if @os_aws.server.nil?

        if number_of_instances == 0
          puts ''
          puts 'No workers requested'
        else
          worker_options = {
              user_id: options[:user_id],
              tags: options[:tags],
              subnet_id: options[:subnet_id],
              associate_public_ip_address: options[:associate_public_ip_address]
          }

          # if options[:ebs_volume_size]
          #   worker_options[:ebs_volume_size] = options[:ebs_volume_size]
          # end

          @os_aws.launch_workers(options[:image_id], options[:instance_type], number_of_instances, worker_options)

          # Add the worker data to the JSON
          save_cluster_json @instances_json

          puts ''
          puts 'Worker SSH Command:'
          @os_aws.workers.each do |worker|
            puts "ssh -i #{@os_aws.private_key_file_name} ubuntu@#{worker.data[:dns]}"
          end
        end

        puts ''
        puts 'Waiting for server/worker configurations'

        @os_aws.configure_server_and_workers
      end

      # Return information on the cluster instances as a hash. This includes IP addresses, host names, number of processors, etc.
      # @return [Hash] Data about the configured cluster
      def cluster_info
        h = @os_aws.server.to_os_hash
        h[:workers] = @os_aws.to_os_worker_hash[:workers]

        h
      end

      # Save a JSON with information about the cluster that was configured.
      # @param filename [String] Path and filename to save the JSON file
      def save_cluster_json(filename)
        File.open(@instances_json, 'w') { |f| f << JSON.pretty_generate(cluster_info) }
      end

      # openstudio_instance_type as symbol
      def stop_instances(group_id, openstudio_instance_type)
        instances = @os_aws.describe_running_instances(group_id, openstudio_instance_type.to_sym)
        ids = instances.map { |k, _| k[:instance_id] }

        resp = []
        resp = @os_aws.stop_instances(ids).to_hash unless ids.empty?
        resp
      end

      # @params(ids): array of instance ids
      def terminate_instances(ids)
        puts "Terminating the following instances #{ids}"
        resp = []
        resp = @os_aws.terminate_instances(ids).to_hash unless ids.empty?
        resp
      end

      # Warning, this appears that it terminates all the instances of the openstudio_instance_type
      def terminate_instances_by_group_id(group_id, openstudio_instance_type)
        instances = @os_aws.describe_running_instances(group_id, openstudio_instance_type.to_sym)
        ids = instances.map { |k, _| k[:instance_id] }

        puts "Terminating the following instances #{ids}"
        resp = []
        resp = @os_aws.terminate_instances(ids).to_hash unless ids.empty?
        resp
      end

      def load_instance_info_from_file(filename)
        fail 'Could not find instance description JSON file' unless File.exist? filename

        h = JSON.parse(File.read(filename), symbolize_names: true)
        @os_aws.find_server(h)

        # load the worker nodes someday
      end

      # Send a file to the server or worker nodes
      def upload_file(server_or_workers, local_file, remote_file)
        case server_or_workers
          when :server
            fail 'Server node is nil' unless @os_aws.server
            return @os_aws.server.upload_file(local_file, remote_file)
          when :worker
            fail 'Worker list is empty' if @os_aws.workers.empty?
            return @os_aws.workers.each { |w| w.upload_file(local_file, remote_file) }
        end
      end

      def shell_command(server_or_workers, command, load_env = true)
        case server_or_workers
          when :server
            fail 'Server node is nil' unless @os_aws.server
            return @os_aws.server.shell_command(command, load_env)
          when :worker
            fail 'Worker list is empty' if @os_aws.workers.empty?
            return @os_aws.workers.each { |w| w.shell_command(command, load_env) }
        end
      end

      # Download remote files that are on the server or worker.  note that the worker at the moment
      # will not work because it would simply overwrite the downloaded filas at this time.
      def download_remote_file(server_or_workers, remote_file, local_file)
        case server_or_workers
          when :server
            fail 'Server node is nil' unless @os_aws.server
            return @os_aws.server.download_file(remote_file, local_file)
          when :worker
            fail 'Worker file download is not available'
        end
      end

      def determine_image_type(instance_type)
        image = nil
        if instance_type =~ /cc2/
          image = @default_amis[:cc2worker]
        else
          image = @default_amis[:worker]
        end

        image
      end

      private

      def os_aws_file_location
        # Get the location of the os-aws.rb file.  Use the relative path from where this file exists
        os_aws_file = File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'os-aws.rb'))
        fail "os_aws_file does not exist where it is expected: #{os_aws_file}" unless File.exist?(os_aws_file)

        os_aws_file
      end
    end
  end
end
