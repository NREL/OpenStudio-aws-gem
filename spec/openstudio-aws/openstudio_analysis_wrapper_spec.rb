require 'spec_helper'

describe OpenStudioAwsWrapper do
  context 'number of cores' do
    it 'should calculate number of cores' do
      data = {
          save_directory: 'spec/test_data',
          credentials: { access_key_id: 'abcd', secret_access_key: 'efgh', region: 'us-east-1'}
      }
      @os_aws_wrapper = OpenStudioAwsWrapper.new(data)


      proc_arr = @os_aws_wrapper.calculate_processors(356)
      # total_procs
      expect(proc_arr[0]).to eq 340
    end
  end
end
