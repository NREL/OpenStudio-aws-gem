module OpenStudio
  module Aws
    class Config
      include Logging

      attr_accessor :access_key
      attr_accessor :secret_key

      def initialize(yml_config_file = nil)
        # First check if the AWS keys are set in the env variable, if so, then use those keys
        @access_key = ENV['AWS_ACCESS_KEY_ID'] if ENV['AWS_ACCESS_KEY_ID']
        @secret_key = ENV['AWS_SECRET_ACCESS_KEY'] if ENV['AWS_SECRET_ACCESS_KEY']

        if @access_key && @secret_key
          logger.info 'Using AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment variables'
        else
          # Otherwise read the file
          logger.info 'Reading AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from aws config file'

          @yml_config_file = yml_config_file
          @config = nil

          @yml_config_file = File.join(File.expand_path('~'), 'aws_config.yml') if @yml_config_file.nil?

          unless File.exist?(@yml_config_file)
            write_config_file
            fail "Config file not found. A template has been added, please edit and save: #{@yml_config_file}"
            exit 1
          end

          begin
            @config = YAML.load(File.read(@yml_config_file))

            # always convert to symbolized hash
            @config = @config.inject({}) { |a, (k, v)| a[k.to_sym] = v; a }

            @access_key = @config[:access_key_id]
            @secret_key = @config[:secret_access_key]
          rescue
            raise "Couldn't read config file #{@yml_config_file}. Delete file then recreate by rerunning script"
          end
        end
      end

      private

      def write_config_file
        # create the file
        data = {
          access_key_id: 'YOUR_ACCESS_KEY_ID',
          secret_access_key: 'YOUR_SECRET_ACCESS_KEY'
        }

        File.open(@yml_config_file, 'w') { |f| f << data.to_yaml }
      end
    end
  end
end
