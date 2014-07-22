require 'spec_helper'

describe OpenStudioAwsInstance do
  context 'processors' do
    before :all do
      @aws_instance = OpenStudioAwsInstance.new(nil, nil, nil, nil, nil, nil, nil)
    end

    it 'should default to 1 with a warning' do
      r = @aws_instance.find_processors('unknowninstance')
      expect(r).to eq(1)
    end

    it 'should return known values for various instances' do
      r = @aws_instance.find_processors('c3.8xlarge')
      expect(r).to eq(16)
    end
  end
end
