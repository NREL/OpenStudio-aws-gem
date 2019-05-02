# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2019, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER, THE UNITED STATES
# GOVERNMENT, OR ANY CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

module OpenStudio
  module Aws
    class Config
      include Logging

      attr_accessor :access_key
      attr_accessor :secret_key

      def initialize(yml_config_file = nil)
        # If the AWS keys are set in the env variable and the yml_config_file is nil, then use those keys
        @access_key = ENV['AWS_ACCESS_KEY_ID'] if ENV['AWS_ACCESS_KEY_ID']
        @secret_key = ENV['AWS_SECRET_ACCESS_KEY'] if ENV['AWS_SECRET_ACCESS_KEY']

        if @access_key && @secret_key && yml_config_file.nil?
          logger.info 'Using AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment variables'
        else
          # Otherwise read the file
          logger.info 'Reading AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from aws config file'

          @yml_config_file = yml_config_file
          @config = nil

          @yml_config_file = File.join(File.expand_path('~'), 'aws_config.yml') if @yml_config_file.nil?

          unless File.exist?(@yml_config_file)
            write_config_file
            raise "Config file not found. A template has been added, please edit and save: #{@yml_config_file}"
            exit 1
          end

          begin
            @config = YAML.load(File.read(@yml_config_file))

            # always convert to symbolized hash
            @config = @config.inject({}) { |a, (k, v)| a[k.to_sym] = v; a }

            @access_key = @config[:access_key_id]
            @secret_key = @config[:secret_access_key]
          rescue StandardError
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
