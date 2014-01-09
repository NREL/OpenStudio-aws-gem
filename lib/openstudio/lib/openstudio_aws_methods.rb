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

######################################################################
# == Synopsis
#
#   Uses the aws-sdk gem to communicate with AWS
#
# == Usage
#
#  ruby aws.rb access_key secret_key us-east-1 EC2 launch_server "{\"instance_type\":\"t1.micro\"}"
#
#  ARGV[0] - Access Key
#  ARGV[1] - Secret Key
#  ARGV[2] - Region
#  ARGV[3] - Service (e.g. "EC2" or "CloudWatch")
#  ARGV[4] - Command (e.g. "launch_server")
#  ARGV[5] - Optional json with parameters associated with command
#
######################################################################

module OpenStudioAwsMethods
  def create_struct(instance, procs)
    instance_struct = Struct.new(:instance, :id, :ip, :dns, :procs)
    return instance_struct.new(instance, instance.instance_id, instance.public_ip_address, instance.public_dns_name, procs)
  end

  def find_processors(instance)
    lookup = {
        "m3.xlarge" => 4,
        "m3.2xlarge" => 8,
        "m1.small" => 1,
        "m1.medium" => 1,
        "m1.large" => 2,
        "m1.xlarge" => 4,
        "c3.large" => 2,
        "c3.xlarge" => 4,
        "c3.2xlarge" => 8,
        "c3.4xlarge" => 16,
        "c3.8xlarge" => 16,
        "c1.medium" => 2,
        "c1.xlarge" => 8,
        "cc2.8xlarge" => 16,
        "g2.2xlarge" => 8,
        "cg1.4xlarge" => 16,
        "m2.xlarge" => 2,
        "m2.2xlarge" => 4,
        "m2.4xlarge" => 8,
        "cr1.8xlarge" => 16,
        "hi1.4xlarge" => 16,
        "hs1.8xlarge" => 16,
        "t1.micro" => 1,
    }

    processors = 1
    if lookup.has_key?(instance)
      processors = lookup[instance]
    else
      #logger.warn "Could not find the number of processors for instance type of #{instance}" if logger
    end

    processors
  end


  def upload_file(host, local_path, remote_path)
    retries = 0
    begin
      Net::SCP.start(host, 'ubuntu', :key_data => [@private_key]) do |scp|
        scp.upload! local_path, remote_path
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      return if retries == 5
      retries += 1
      sleep 1
      retry
    rescue
      # Unknown upload error, retry
      return if retries == 5
      retries += 1
      sleep 1
      retry
    end
  end


  def send_command(host, command)
    #retries = 0
    begin
      output = ''
      Net::SSH.start(host, 'ubuntu', :key_data => [@private_key]) do |ssh|
        response = ssh.exec!(command)
        output += response if !response.nil?
      end
      return output
    rescue Net::SSH::HostKeyMismatch => e
      e.remember_host!
      # key mismatch, retry
      #return if retries == 5
      #retries += 1
      sleep 1
      retry
    rescue Net::SSH::AuthenticationFailed
      error(-1, "Incorrect private key")
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      #return if retries == 5
      #retries += 1
      sleep 1
      retry
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
    end
  end

#======================= send command ======================#
# Send a command through SSH Shell to an instance.
# Need to pass instance object and the command as a string.
  def shell_command(host, command)
    begin
      @logger.info("ssh_command #{command}")
      Net::SSH.start(host, 'ubuntu', :key_data => [@private_key]) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec "#{command}" do |ch, success|
            raise "could not execute #{command}" unless success

            # "on_data" is called when the process writes something to stdout
            ch.on_data do |c, data|
              #$stdout.print data
              @logger.info("#{data.inspect}")
            end

            # "on_extended_data" is called when the process writes something to stderr
            ch.on_extended_data do |c, type, data|
              #$stderr.print data
              @logger.info("#{data.inspect}")
            end
          end
        end
      end
    rescue Net::SSH::HostKeyMismatch => e
      e.remember_host!
      @logger.info("key mismatch, retry")
      sleep 1
      retry
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 1
      @logger.info("Not Yet")
      retry
    end
  end

  def wait_command(host, command)
    begin
      flag = 0
      while flag == 0 do
        @logger.info("wait_command #{command}")
        Net::SSH.start(host, 'ubuntu', :key_data => [@private_key]) do |ssh|
          channel = ssh.open_channel do |ch|
            ch.exec "#{command}" do |ch, success|
              raise "could not execute #{command}" unless success

              # "on_data" is called when the process writes something to stdout
              ch.on_data do |c, data|
                @logger.info("#{data.inspect}")
                if data.chomp == "true"
                  @logger.info("wait_command #{command} is true")
                  flag = 1
                else
                  sleep 5
                end
              end

              # "on_extended_data" is called when the process writes something to stderr
              ch.on_extended_data do |c, type, data|
                @logger.info("#{data.inspect}")
                if data == "true"
                  @logger.info("wait_command #{command} is true")
                  flag = 1
                else
                  sleep 5
                end
              end
            end
          end
        end
      end
    rescue Net::SSH::HostKeyMismatch => e
      e.remember_host!
      @logger.info("key mismatch, retry")
      sleep 1
      retry
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 1
      @logger.info("Not Yet")
      retry
    end
  end

  def download_file(host, remote_path, local_path)
    retries = 0
    begin
      Net::SCP.start(host, 'ubuntu', :key_data => [@private_key]) do |scp|
        scp.download! remote_path, local_path
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      return if retries == 5
      retries += 1
      sleep 1
      retry
    rescue
      return if retries == 5
      retries += 1
      sleep 1
      retry
    end
  end
end
