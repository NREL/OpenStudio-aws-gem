require 'spec_helper'

describe OpenStudioAwsMethods do
  class DummyClass
  end

  before :each do
    @dummy_class = DummyClass.new
    @dummy_class.extend(OpenStudioAwsMethods)
  end

  context 'processors' do
    it 'should default to 1 with a warning' do
      r = @dummy_class.find_processors('unknowninstance')
      expect(r).to eq(1)
    end

    it 'should return known values for various instances' do
      r = @dummy_class.find_processors('c3.8xlarge')
      expect(r).to eq(16)
    end

  end
end
