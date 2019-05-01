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

require 'spec_helper'

describe OpenStudio::Aws::Config do
  context 'create a new config' do
    it 'should create a new instance' do
      @config = OpenStudio::Aws::Config.new
      expect(@config).not_to be_nil
    end

    it 'should create a new file' do
      local_file = 'test.config'
      File.delete local_file if File.exist? local_file

      expect { OpenStudio::Aws::Config.new local_file }.to raise_error /Config file not found. A template has been added, please edit and save: test.config/
      expect(File.exist?(local_file)).to eq true

      # read the file and make sure that the template is there
      config = YAML.load(File.read(local_file))
      expect(config[:access_key_id]).to eq 'YOUR_ACCESS_KEY_ID'
      expect(config[:secret_access_key]).to eq 'YOUR_SECRET_ACCESS_KEY'
    end

    it 'should read old format' do
      # make sure that we can read the old format which has non-symoblized keys
      local_file = 'test_custom_old.config'

      data = {
        'access_key_id' =>  'abcd',
        'secret_access_key' => 'efgh'
      }

      File.open(local_file, 'w') { |f| f << data.to_yaml }
      config = OpenStudio::Aws::Config.new local_file
      expect(config.access_key).to eq 'abcd'
      expect(config.secret_key).to eq 'efgh'
    end

    it 'should read a custom file' do
      local_file = 'test_custom.config'

      # create the file
      data = {
        access_key_id: 'random_key',
        secret_access_key: 'random_secret_key'
      }

      File.open(local_file, 'w') { |f| f << data.to_yaml }

      config = OpenStudio::Aws::Config.new local_file
      expect(config.access_key).to eq 'random_key'
      expect(config.secret_key).to eq 'random_secret_key'
    end
  end
end
