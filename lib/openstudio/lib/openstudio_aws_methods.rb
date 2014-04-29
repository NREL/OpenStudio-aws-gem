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
#   Methods module for openstudio aws
#
# == Usage
#
#  Inside the class in which this file is included make sure to implement the following
#  
#  Member Variables:
#    private_key : the in memory private key
#    logger : logger class in which to write log messages
#    @proxy : proxy setting if available 
######################################################################

module OpenStudioAwsMethods
  # This list of processors can be pulled out of the ../../doc/amazon_prices.xlsx file
  def find_processors(instance)
    lookup = {
        "m3.medium" => 1,
        "m3.large" => 2,
        "m3.xlarge" => 4,
        "m3.2xlarge" => 8,
        "c3.large" => 2,
        "c3.xlarge" => 4,
        "c3.2xlarge" => 8,
        "c3.4xlarge" => 16,
        "c3.8xlarge" => 16,
        "r3.large" => 2,
        "r3.xlarge" => 4,
        "r3.2xlarge" => 8,
        "r3.4xlarge" => 16,
        "r3.8xlarge" => 32,
        "t1.micro" => 1,
        "m1.small" => 1,
    }

    processors = 1
    if lookup.has_key?(instance)
      processors = lookup[instance]
    else
      #logger.warn "Could not find the number of processors for instance type of #{instance}" if logger
    end

    processors
  end

  def get_proxy()
    proxy = nil
    if @proxy
      if @proxy[:username]
        proxy = Net::SSH::Proxy::HTTP.new(@proxy[:host], @proxy[:port], :user => @proxy[:username], :password => proxy[:password])
      else
        proxy = Net::SSH::Proxy::HTTP.new(@proxy[:host], @proxy[:port])
      end
    end
    
    proxy
  end
  
  
  def upload_file(host, local_path, remote_path)
    retries = 0
    begin
      Net::SCP.start(host, 'ubuntu', :proxy => get_proxy, :key_data => [@private_key]) do |scp|
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
      Net::SSH.start(host, 'ubuntu', :proxy => get_proxy, :key_data => [@private_key]) do |ssh|
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
      Net::SSH.start(host, 'ubuntu', :proxy => get_proxy, :key_data => [@private_key]) do |ssh|
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
        Net::SSH.start(host, 'ubuntu', :proxy => get_proxy, :key_data => [@private_key]) do |ssh|
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
      sleep 5
      retry
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 5
      @logger.info("Timeout.  Perhaps there is a communication error to EC2?  Will try again")
      retry
    end
  end

  def download_file(host, remote_path, local_path)
    retries = 0
    begin
      Net::SCP.start(host, 'ubuntu', :proxy => get_proxy, :key_data => [@private_key]) do |scp|
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
