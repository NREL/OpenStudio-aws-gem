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

describe OpenStudioAmis do
  context 'version 1' do
    it 'should default to an ami if nothing passed' do
      a = OpenStudioAmis.new
      amis = a.get_amis

      expect(amis[:server]).not_to be_nil
      expect(amis[:worker]).not_to be_nil

      # From OpenStudio Version 1.5.0 expect cc2workers to be null
      expect(amis[:cc2worker]).to be_nil
    end

    it 'should return specific amis if passed a version' do
      a = OpenStudioAmis.new(1, openstudio_version: '1.13.2')
      amis = a.get_amis

      expect(amis[:server]).to eq('ami-e7a1bbf0')
      expect(amis[:worker]).to eq('ami-e0a1bbf7')
    end

    it 'should list all amis' do
      a = OpenStudioAmis.new(1).list

      expect(a).not_to be_nil
    end
  end

  context 'version 2' do
    it 'should fail when trying to find a stable version for older releases' do
      a = OpenStudioAmis.new(2, openstudio_version: '1.5.0', stable: true)

      expect { a.get_amis }.to raise_error(/Could not find a stable version for openstudio version 1.5.0/)
    end
  end

  context 'version 3' do
    it 'should fail when trying to find a stable version for older releases' do
      a = OpenStudioAmis.new(3, openstudio_version: '2.8.0', stable: true)

      puts a.inspect

      expect { a.get_amis }.to raise_error(/Currently the openstudio_version lookup is not supported in v3/)
    end
  end
end
