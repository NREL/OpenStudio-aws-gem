# NOTE: Do not modify this file as it is copied over. Modify the source file and rerun rake import_files
######################################################################
#  Copyright (c) 2008-2014, Alliance for Sustainable Energy.
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

# Class for managing the AMI ids based on the openstudio version and the openstudio-server version

class OpenStudioAmis
  VALID_OPTIONS = [
    :openstudio_version, :openstudio_server_version, :host, :url
  ]

  def initialize(version = 1, options = {})
    invalid_options = options.keys - VALID_OPTIONS
    if invalid_options.any?
      fail ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
    end

    # merge in some defaults
    defaults = {
      openstudio_version: 'default',
      openstudio_server_version: 'default',
      host: 'developer.nrel.gov',
      url: '/downloads/buildings/openstudio/api'
    }
    @version = version
    @options = defaults.merge(options)
  end

  def list
    json = nil
    command = "list_amis_version_#{@version}"
    if OpenStudioAmis.method_defined?(command)
      json = send(command)
    else
      fail "Unknown api version command #{command}"
    end

    json
  end

  def get_amis
    amis = nil
    command = "get_ami_version_#{@version}"
    if OpenStudioAmis.method_defined?(command)
      amis = send(command)
    else
      fail "Unknown api version command #{command}"
    end

    fail "Could not find any amis for #{@version}" if amis.nil?

    amis
  end

  protected

  def list_amis_version_1
    endpoint = "#{@options[:url]}/amis_v1.json"
    json = retrieve_json(endpoint)

    json
  end

  def list_amis_version_2
    endpoint = "#{@options[:url]}/amis_v2.json"

    json = retrieve_json(endpoint)
    json
  end

  def get_ami_version_1
    json = list_amis_version_1
    version = json.key?(@options[:openstudio_version].to_sym) ? @options[:openstudio_version].to_sym : 'default'

    json[version]
  end

  def get_ami_version_2
    json = list_amis_version_2

    amis = nil
    if @options[:openstudio_server_version].to_sym == :default
      # just grab the most recent server
      # need to do a sort to get the most recent because we can't promise that they are in order
      key, value = json[:openstudio_server].first

      amis = value[:amis]
      # puts json.inspect
    else
      value = json[:openstudio_server][@options[:openstudio_server_version].to_sym]
      amis = value[:amis]
    end

    amis
  end

  private

  # fetch the URL with redirects
  def fetch(uri_str, limit = 10)
    # You should choose better exception.
    fail ArgumentError, 'HTTP redirect too deep' if limit == 0

    url = URI.parse(uri_str)
    req = Net::HTTP::Get.new(url.path)
    response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
    case response
      when Net::HTTPSuccess then
        response
      when Net::HTTPRedirection then
        fetch(response['location'], limit - 1)
      else
        response.error!
    end
  end

  def retrieve_json(endpoint)
    result = nil
    resp = fetch("http://#{@options[:host]}/#{endpoint}")
    if resp.code == '200'
      result = JSON.parse(resp.body, symbolize_names: true)
    else
      fail "#{resp.code} Unable to download AMI IDs"
    end

    result
  end
end
