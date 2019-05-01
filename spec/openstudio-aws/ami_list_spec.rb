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
