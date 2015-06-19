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
  include Logging

  VALID_OPTIONS = [
    :openstudio_version, :openstudio_server_version, :host, :url, :stable
  ]

  # Initializer for listing the AMIs and grabbing the correct version of the AMIs based on the OpenStudio version or
  # OpenStudio Server version.
  #
  # @param version [Double] Version of the JSON to return. Currently only version 1 or 2
  # @param options [Hash] Values to operate on
  # @option options [String] :openstudio_version Version of OpenStudio to perform the AMI lookup
  # @option options [String] :openstudio_server_version Version of the OpenStudio to perform the AMI lookup
  def initialize(version = 1, options = {})
    invalid_options = options.keys - VALID_OPTIONS
    if invalid_options.any?
      fail ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
    end

    if options[:openstudio_version] && options[:openstudio_server_version]
      fail 'Must pass only an openstudio_version or openstudio_server_version when looking up AMIs'
    end

    # merge in some defaults
    defaults = {
      openstudio_version: 'default',
      openstudio_server_version: 'default',
      # host: 'developer.nrel.gov',
      # url: '/downloads/buildings/openstudio/api'
      host: 's3.amazonaws.com',
      url: '/openstudio-resources/server/api'
    }

    @version = version
    @options = defaults.merge(options)

    if @options[:openstudio_version] != 'default' && @options[:openstudio_server_version] != 'default'
      fail 'Must pass either the openstudio_version or openstudio_server_version when looking up AMIs, not both'
    end
  end

  # List the AMIs based on the version and host. This method does catch old 'developer.nrel.gov' hosts and formats
  # the endpoint using the old '<host>/<url>/amis_#{version}.json' instead of the new, more restful, syntax of
  # <host>/<url>/v#{version}/amis.json
  def list
    endpoint = nil

    # for backwards compatibility with developer
    if @options[:host] =~ /developer.nrel/
      endpoint = "#{@options[:url]}/amis_v#{@version}.json"
    else
      endpoint = "#{@options[:url]}/v#{@version}/amis.json"
    end

    retrieve_json(endpoint)
  end

  # Return the AMIs for the specific openstudio_version or openstudio_server_version
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

  def get_ami_version_1
    json = list
    version = json.key?(@options[:openstudio_version].to_sym) ? @options[:openstudio_version].to_sym : 'default'

    json[version]
  end

  # Return the AMIs for the server and worker. Version 2 also does a lookup of the stable version
  def get_ami_version_2
    json = list

    amis = nil
    if @options[:openstudio_version].to_sym == :default && @options[:openstudio_server_version].to_sym == :default
      # grab the most recent openstudio server version - this is not recommended
      key, value = json[:openstudio_server].first
      amis = value[:amis]
    elsif @options[:openstudio_server_version] != 'default'
      value = json[:openstudio_server][@options[:openstudio_server_version].to_sym]
      amis = value[:amis]
    elsif @options[:openstudio_version] != 'default'
      if @options[:stable]
        stable = json[:openstudio][@options[:openstudio_version].to_sym][:stable]
        if stable
          value = json[:openstudio][@options[:openstudio_version].to_sym][stable.to_sym]
          amis = value[:amis]
        else
          logger.info "Could not find a stable version for OpenStudio version #{@options[:openstudio_version]}. "\
                      'Looking up older versions to find the latest stable.' unless stable

          json[:openstudio].each do |os_version, values|
            next if os_version == :default
            if values.key? :stable
              # don't check versions newer than what we are requesting
              next if os_version.to_s.to_version > @options[:openstudio_version].to_s.to_version
              stable = json[:openstudio][os_version][:stable]
              logger.info "Found a stable version for OpenStudio version #{os_version} with OpenStudio Server version #{stable}"
              value = values[stable.to_sym]
              amis = value[:amis]

              break
            end
          end

          fail "Could not find a stable version for openstudio version #{@options[:openstudio_version]}" unless amis
        end
      else
        # return the default version (which is the latest)
        default = json[:openstudio][@options[:openstudio_version].to_sym][:default]
        fail "Could not find a default version for openstudio version #{@options[:openstudio_version]}" unless default
        value = json[:openstudio][@options[:openstudio_version].to_sym][default.to_sym]
        amis = value[:amis]
      end
    end

    logger.info "AMI IDs are #{amis}" if amis

    amis
  end

  private

  # fetch the URL with redirects
  def fetch(uri_str, limit = 10)
    # You should choose better exception.
    fail ArgumentError, 'HTTP redirect too deep' if limit == 0

    url = URI.parse(uri_str)
    req = Net::HTTP::Get.new(url.path)
    logger.info "Fetching AMI list from #{uri_str}"
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
