# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2019, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER, THE UNITED STATES
# GOVERNMENT, OR ANY CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

# Class for managing the AMI ids based on the openstudio version and the openstudio-server version

class OpenStudioAmis
  include Logging

  VALID_OPTIONS = [
    :openstudio_version, :openstudio_server_version, :host, :url, :stable
  ].freeze

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
      raise ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
    end

    if options[:openstudio_version] && options[:openstudio_server_version]
      raise 'Must pass only an openstudio_version or openstudio_server_version when looking up AMIs'
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
      raise 'Must pass either the openstudio_version or openstudio_server_version when looking up AMIs, not both'
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
      raise "Unknown api version command #{command}"
    end

    raise "Could not find any amis for #{@version}" if amis.nil?

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
        stable = nil
        if json[:openstudio][@options[:openstudio_version].to_sym]
          stable = json[:openstudio][@options[:openstudio_version].to_sym][:stable]
          logger.info "The stable version in the JSON is #{stable}"
        end

        if stable
          value = json[:openstudio_server][stable.to_sym]
          amis = value[:amis]
        else
          unless stable
            logger.info "Could not find a stable version for OpenStudio version #{@options[:openstudio_version]}. "\
                        'Looking up older versions to find the latest stable.'
          end

          json[:openstudio].each do |os_version, values|
            next if os_version == :default

            if values.key? :stable
              # don't check versions newer than what we are requesting
              next if os_version.to_s.to_version > @options[:openstudio_version].to_s.to_version

              stable = json[:openstudio][os_version][:stable]
              logger.info "Found a stable version for OpenStudio version #{os_version} with OpenStudio Server version #{stable}"
              value = json[:openstudio_server][stable.to_sym]
              amis = value[:amis]

              break
            end
          end

          raise "Could not find a stable version for openstudio version #{@options[:openstudio_version]}" unless amis
        end
      else
        # return the default version (which is the latest)
        default = json[:openstudio][@options[:openstudio_version].to_sym][:default]
        raise "Could not find a default version for openstudio version #{@options[:openstudio_version]}" unless default

        value = json[:openstudio][@options[:openstudio_version].to_sym][default.to_sym]
        amis = value[:amis]
      end
    end

    logger.info "AMI IDs are #{amis}" if amis

    amis
  end

  # Return the required docker AMI base box
  def get_ami_version_3
    json = list
    amis = nil
    if @options[:openstudio_version].to_sym == :default && @options[:openstudio_server_version].to_sym == :default
      # grab the most recent openstudio server version - this is not recommended
      value = json[:builds].first
      amis = {}
      amis[:server] = value[:ami]
      amis[:worker] = value[:ami]
    elsif @options[:openstudio_server_version] != 'default'
      hash_array = json[:builds]
      hash = hash_array.select { |hash| hash[:name] == @options[:openstudio_server_version] }
      raise "Multiple | no entries found matching name key `#{@options[:openstudio_server_version]}`" unless hash.length == 1

      amis = {}
      amis[:server] = hash.first[:ami]
      amis[:worker] = hash.first[:ami]
    elsif @options[:openstudio_version] != 'default'
      raise 'Currently the openstudio_version lookup is not supported in v3.'
    end
    raise 'The requested AMI key is NULL.' if amis[:server].nil?

    logger.info "AMI IDs are #{amis}" if amis

    amis
  end

  private

  # fetch the URL with redirects
  def fetch(uri_str, limit = 10)
    # You should choose better exception.
    raise ArgumentError, 'HTTP redirect too deep' if limit == 0

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
      raise "#{resp.code} Unable to download AMI IDs"
    end

    result
  end
end
