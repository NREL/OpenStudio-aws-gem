require 'spec_helper'

describe OpenStudioAmis do
  context 'version 1' do
    it 'should default to an ami if nothing passed' do
      a = OpenStudioAmis.new
      amis = a.get_amis

      expect(amis[:server]).not_to be_nil
      expect(amis[:worker]).not_to be_nil

      # From OpenStudio Version 1.5.0 expect cc2workers to be the same as the worker
      expect(amis[:cc2worker]).not_to be_nil
      expect(amis[:worker]).to eq amis[:cc2worker]
      puts amis.inspect
    end

    it 'should return specific amis if passed a version' do
      a = OpenStudioAmis.new(1, openstudio_version: '1.2.0')

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-a3edddca')
      expect(amis[:worker]).to eq('ami-bfedddd6')
      expect(amis[:cc2worker]).to eq('ami-b5eddddc')
    end

    it 'should list all amis' do
      a = OpenStudioAmis.new(1).list

      expect(a).not_to be_nil
    end
  end

  context 'version 2' do
    it 'should return 1.8.0 versions correctly' do
      a = OpenStudioAmis.new(2, openstudio_server_version: '1.8.0')

      amis = a.get_amis

      expect(amis[:server]).to eq('ami-3c0fbf54')
      expect(amis[:worker]).to eq('ami-040ebe6c')
      expect(amis[:cc2worker]).to eq('ami-040ebe6c')
    end
  end
end
