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

require_relative 'openstudio_aws_wrapper'
require_relative 'openstudio_aws_instance'
require 'aws-sdk-core'
require 'json'
require 'logger'
require 'net/http'
require 'net/scp'
require 'net/ssh'
require 'tempfile'
require 'time'
require 'base64'

def error(code, msg)
  puts (
           {
               :error => {
                   :code => code, :message => msg
               },
               :arguments => ARGV[2..-1]
           }.to_json
       )
  exit(1)
end

if ARGV.length < 5
  error(-1, 'Invalid number of args')
end

if ARGV[0].empty? || ARGV[1].empty?
  error(401, 'Missing authentication arguments')
end

if ARGV[2].empty?
  error(-1, 'Missing region argument')
end

if ARGV[3].empty?
  error(-1, 'Missing service argument')
end

if ARGV[4].empty?
  error(-1, 'Missing command argument')
end

Aws.config = {:access_key_id => ARGV[0], :secret_access_key => ARGV[1], :region => ARGV[2], :ssl_verify_peer => false}

if ARGV[3] == 'EC2'
  @aws = Aws::EC2.new
elsif ARGV[3] == 'CloudWatch'
  @aws = AWS::CloudWatch.new
else
  error(-1, "Unrecognized AWS service: #{ARGV[3]}")
end

if ARGV.length == 6
  @params = JSON.parse(ARGV[5])
  OPENSTUDIO_VERSION = @params['openstudio_version'] if @params.include?('openstudio_version')
  @server_image_id = @params['server_ami'] if @params.include?('server_ami')
  @worker_image_id = @params['worker_ami'] if @params.include?('worker_ami')
end

OPENSTUDIO_VERSION = '1.1.4' unless defined?(OPENSTUDIO_VERSION)

if (!defined?(@server_image_id) || !defined?(@worker_image_id))
  resp = Net::HTTP.get_response('developer.nrel.gov', '/downloads/buildings/openstudio/rsrc/amis.json')
  if resp.code == '200'
    result = JSON.parse(resp.body)
    version = result.has_key?(OPENSTUDIO_VERSION) ? OPENSTUDIO_VERSION : 'default'

    @server_image_id = result[version]['server']
    if ARGV.length >= 6 && @params['instance_type'] == 'cc2.8xlarge'
      @worker_image_id = result[version]['cc2worker']
    else
      @worker_image_id = result[version]['worker']
    end
  else
    error(resp.code, 'Unable to download AMI IDs')
  end
end

begin
  @logger = Logger.new(File.expand_path("~/.aws.log"))
  @logger.info("initialized")
  case ARGV[4]
    when 'describe_availability_zones'
      os_aws = OpenStudioAwsWrapper.new
      resp = os_aws.describe_availability_zones_json
      puts resp
      @logger.info("availability_zones #{resp}")
    when 'total_instances'
      os_aws = OpenStudioAwsWrapper.new
      resp = os_aws.describe_total_instances_json
      puts resp
    when 'instance_status'
      resp = nil
      if ARGV.length < 6
        resp = @aws.client.describe_instance_status
      else
        resp = @aws.client.describe_instance_status({:instance_ids => [@params['instance_id']]})
      end
      output = Hash.new
      resp.data[:instance_status_set].each { |instance|
        output[instance[:instance_id]] = instance[:instance_state][:name]
      }
      puts output.to_json
    when 'launch_server'
      if ARGV.length < 6
        error(-1, 'Invalid number of args')
      end
      os_aws = OpenStudioAwsWrapper.new
      os_aws.create_or_retrieve_security_group("openstudio-worker-sg-v1")
      os_aws.create_or_retrieve_key_pair

      @server_instance_type = @params['instance_type']
      begin
        os_aws.launch_server(@server_image_id, @server_instance_type)
      rescue Exception => e
        error(-1, "Server status: #{e.message}")
      end

      puts os_aws.server.to_os_json

    when 'launch_workers'
      @timestamp = @params['timestamp']
      
      os_aws = OpenStudioAwsWrapper.new(nil, @timestamp) # todo: pass in the groupuuid not the timestamp
      
      os_aws.find_server() 
      os_aws.create_or_retrieve_security_group("openstudio-worker-sg-v1")
      os_aws.create_or_retrieve_key_pair

      if ARGV.length < 6
        error(-1, 'Invalid number of args')
      end
      if @params['num'] < 1
        error(-1, 'Invalid number of worker nodes, must be greater than 0')
      end
      
      @worker_instance_type = @params['instance_type']
      begin
        os_aws.launch_workers(@worker_image_id, @worker_instance_type, @params['num'])
      rescue Exception => e
        error(-1, "Server status: #{e.message}")
      end

      @workers = []

      exit
      
      # find if an existing openstudio-server-vX security group exists and use that
      @group = @aws.security_groups.filter('group-name', 'openstudio-worker-sg-v1').first
      if @group.nil?
        @group = @aws.security_groups.create('openstudio-worker-sg-v1')
        @group.allow_ping() # allow ping
        @group.authorize_ingress(:tcp, 1..65535) # all traffic
      end
      @logger.info("worker_group #{@group}")
      @key_pair = @aws.key_pairs.filter('key-name', "key-pair-#{@timestamp}").first
      @private_key = File.read(@params['private_key'])
      @worker_instance_type = @params['instance_type']
      @server = @aws.instances[@params['server_id']]
      error(-1, 'Server node does not exist') unless @server.exists?
      @server = create_struct(@server, @params['server_procs'])

      launch_workers(@params['num'], @server.ip)
      #@workers.push(create_struct(@aws.instances['i-xxxxxxxx'], 1))
      #processors = send_command(@workers[0].ip, 'nproc | tr -d "\n"')
      #@workers[0].procs = processors

      #wait for user_data to complete execution
      @logger.info("server user_data")
      wait_command(@server.ip, '[ -e /home/ubuntu/user_data_done ] && echo "true"')
      @logger.info("worker user_data")
      @workers.each { |worker| wait_command(worker.ip, '[ -e /home/ubuntu/user_data_done ] && echo "true"') }
      #wait_command(@workers.first.ip, "[ -e /home/ubuntu/user_data_done ] && echo 'true'") 


      ips = "master|#{@server.ip}|#{@server.dns}|#{@server.procs}|ubuntu|ubuntu\n"
      @workers.each { |worker| ips << "worker|#{worker.ip}|#{worker.dns}|#{worker.procs}|ubuntu|ubuntu|true\n" }
      file = Tempfile.new('ip_addresses')
      file.write(ips)
      file.close
      upload_file(@server.ip, file.path, 'ip_addresses')
      file.unlink
      @logger.info("ips #{ips}")
      shell_command(@server.ip, 'chmod 664 /home/ubuntu/ip_addresses')
      shell_command(@server.ip, '~/setup-ssh-keys.sh')
      shell_command(@server.ip, '~/setup-ssh-worker-nodes.sh ip_addresses')

      mongoid = File.read(File.expand_path(File.dirname(__FILE__))+'/mongoid.yml.template')
      mongoid.gsub!(/SERVER_IP/, @server.ip)
      file = Tempfile.new('mongoid.yml')
      file.write(mongoid)
      file.close
      upload_file(@server.ip, file.path, '/mnt/openstudio/rails-models/mongoid.yml')
      @workers.each { |worker| upload_file(worker.ip, file.path, '/mnt/openstudio/rails-models/mongoid.yml') }
      file.unlink

      # Does this command crash it?
      shell_command(@server.ip, 'chmod 664 /mnt/openstudio/rails-models/mongoid.yml')
      @workers.each { |worker| shell_command(worker.ip, 'chmod 664 /mnt/openstudio/rails-models/mongoid.yml') }

      worker_json = []
      @workers.each { |worker|
        worker_json.push({
                             :id => worker.id,
                             :ip => 'http://' + worker.ip,
                             :dns => worker.dns,
                             :procs => worker.procs
                         })
      }
      puts ({:workers => worker_json}.to_json)
      @logger.info("workers #{({:workers => worker_json}.to_json)}")
    when 'terminate_session'
      if ARGV.length < 6
        error(-1, 'Invalid number of args')
      end
      instances = []

      server = @aws.instances[@params['server_id']]
      error(-1, "Server node #{@params['server_id']} does not exist") unless server.exists?

      #@timestamp = @aws.client.describe_instances({:instance_ids=>[@params['server_id']]}).data[:instance_index][@params['server_id']][:key_name][9,10]
      @timestamp = server.key_name[9, 10]

      instances.push(server)
      @params['worker_ids'].each { |worker_id|
        worker = @aws.instances[worker_id]
        error(-1, "Worker node #{worker_id} does not exist") unless worker.exists?
        instances.push(worker)
      }

      instances.each { |instance|
        instance.terminate
      }
      sleep 5 while instances.any? { |instance| instance.status != :terminated }

      # When session is fully terminated, then delete the key pair
      #@aws.client.delete_security_group({:group_name=>'openstudio-server-sg-v1'}"})
      #@aws.client.delete_security_group({:group_name=>'openstudio-worker-sg-v1'}"})
      @aws.client.delete_key_pair({:key_name => "key-pair-#{@timestamp}"})

    when 'termination_status'
      if ARGV.length < 6
        error(-1, 'Invalid number of args')
      end
      notTerminated = 0

      server = @aws.instances[@params['server_id']]
      notTerminated += 1 if (server.exists? && server.status != :terminated)

      @params['worker_ids'].each { |worker_id|
        worker = @aws.instances[worker_id]
        notTerminated += 1 if (worker.exists? && worker.status != :terminated)
      }

      puts ({:all_instances_terminated => (notTerminated == 0)}.to_json)

    when 'session_uptime'
      if ARGV.length < 6
        error(-1, 'Invalid number of args')
      end
      server_id = @params['server_id']
      #No need to call AWS, but we can
      #minutes = (Time.now.to_i - @aws.client.describe_instances({:instance_ids=>[server_id]}).data[:instance_index][server_id][:launch_time].to_i)/60
      minutes = (Time.now.to_i - @params['timestamp'].to_i)/60
      puts ({:session_uptime => minutes}.to_json)

    when 'estimated_charges'
      endTime = Time.now.utc
      startTime = endTime - 86400
      resp = @aws.client.get_metric_statistics({:dimensions => [{:name => 'ServiceName', :value => 'AmazonEC2'}, {:name => 'Currency', :value => 'USD'}], :metric_name => 'EstimatedCharges', :namespace => 'AWS/Billing', :start_time => startTime.iso8601, :end_time => endTime.iso8601, :period => 300, :statistics => ['Maximum']})
      error(-1, 'No Billing Data') if resp.data[:datapoints].length == 0
      datapoints = resp.data[:datapoints]
      datapoints.sort! { |a, b| a[:timestamp] <=> b[:timestamp] }
      puts ({:estimated_charges => datapoints[-1][:maximum],
             :timestamp => datapoints[-1][:timestamp].to_i}.to_json)

    else
      error(-1, "Unknown command: #{ARGV[4]} (#{ARGV[3]})")
  end
    #puts \"Status: #{resp.http_response.status}\"
rescue SystemExit => e
rescue Exception => e
  if e.message == 'getaddrinfo: No such host is known. '
    error(503, 'Offline')
  elsif defined? e.http_response
    error(e.http_response.status, e.code)
  else
    error(-1, "#{e}: #{e.backtrace}")
  end

end
