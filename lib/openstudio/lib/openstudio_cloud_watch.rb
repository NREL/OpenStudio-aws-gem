######################################################################
#  Copyright (c) 2008-2015, Alliance for Sustainable Energy.
#  All rights reserved.
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with this library; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
######################################################################

require_relative 'openstudio_aws_logger'

class OpenStudioCloudWatch
  include Logging

  attr_accessor :private_key_file_name
  attr_accessor :security_groups

  VALID_OPTIONS = [:proxy, :credentials]

  def initialize(options = {})
    # store an instance variable with the proxy for passing to instances for use in scp/ssh
    @proxy = options[:proxy] ? options[:proxy] : nil

    # need to remove the prxoy information here
    @aws = Aws::CloudWatch::Client.new(options[:credentials])
  end

  def estimated_charges
    end_time = Time.now.utc
    start_time = end_time - 86400
    resp = @aws.get_metric_statistics(
        dimensions: [
            {name: 'ServiceName', value: 'AmazonEC2'},
            {name: 'Currency', value: 'USD'}],
        metric_name: 'EstimatedCharges',
        namespace: 'AWS/Billing',
        start_time: start_time.iso8601,
        end_time: end_time.iso8601,
        period: 300,
        statistics: ['Maximum']
    )

    resp.data || []
  end
end
