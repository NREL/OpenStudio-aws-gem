require 'spec_helper'

describe OpenStudio::Aws::Config do
  context 'create a new config' do
    it 'should create a new instance' do
      @config = OpenStudio::Aws::Config.new
      expect { @config }.not_to be_nil
    end
  end

end
