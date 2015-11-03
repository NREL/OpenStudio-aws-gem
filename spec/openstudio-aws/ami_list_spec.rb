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
      a = OpenStudioAmis.new(1, openstudio_version: '1.2.1')
      amis = a.get_amis

      expect(amis[:server]).to eq('ami-89744be0')
      expect(amis[:worker]).to eq('ami-37744b5e')
      expect(amis[:cc2worker]).to eq('ami-51744b38')
    end

    it 'should list all amis' do
      a = OpenStudioAmis.new(1).list

      expect(a).not_to be_nil
    end
  end

  context 'version 2' do
    it 'should return openstudio server version 1.8.0 correctly' do
      a = OpenStudioAmis.new(2, openstudio_server_version: '1.8.0')

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-3c0fbf54')
      expect(amis[:worker]).to eq('ami-040ebe6c')
      expect(amis[:cc2worker]).to eq('ami-040ebe6c')
    end
  end

  context 'version 2' do
    it 'should return openstudio version 1.7.1 when stable is passed to 1.7.5' do
      a = OpenStudioAmis.new(2, openstudio_version: '1.7.5', stable: true)

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-845a54ec')
      expect(amis[:worker]).to eq('ami-3a5a5452')
    end

    it 'should return openstudio version 1.7.1 stable & default versions correctly' do
      a = OpenStudioAmis.new(2, openstudio_version: '1.7.1')

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-845a54ec')
      expect(amis[:worker]).to eq('ami-3a5a5452')
    end

    it 'should return openstudio version 1.7.0 default version correctly' do
      a = OpenStudioAmis.new(2, openstudio_version: '1.7.0')

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-725b701a')
      expect(amis[:worker]).to eq('ami-4a446f22')
    end

    it 'should return openstudio version 1.7.0 stable version correctly' do
      a = OpenStudioAmis.new(2, openstudio_version: '1.7.0', stable: true)

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-c06b40a8')
      expect(amis[:worker]).to eq('ami-9a97bff2')
    end

    it 'should fail when trying to find a stable version for older releases' do
      a = OpenStudioAmis.new(2, openstudio_version: '1.5.0', stable: true)

      expect { a.get_amis }.to raise_error(/Could not find a stable version for openstudio version 1.5.0/)
    end

    it 'should return latest version when passing in a future version' do
      a = OpenStudioAmis.new(2, openstudio_version: '4.8.15', stable: true)

      a = a.get_amis

      expect(a).not_to be nil
    end
  end
end
