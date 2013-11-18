# This is taken out of the OpenStudio AWS config file to do some testing
#def send_command(host, command, key)
#  require 'net/http'
#  require 'net/scp'
#  require 'net/ssh'
#
#  retries = 0
#  begin
#    puts "connecting.."
#    output = ''
#    Net::SSH.start(host, 'ubuntu', :key_data => [key]) do |ssh|
#      response = ssh.exec!(command)
#      output += response if !response.nil?
#    end
#    return output
#  rescue Net::SSH::HostKeyMismatch => e
#    e.remember_host!
#    # key mismatch, retry
#    return if retries == 2
#    retries += 1
#    sleep 1
#    retry
#  rescue Net::SSH::AuthenticationFailed
#    error(-1, "Incorrect private key")
#  rescue SystemCallError, Timeout::Error => e
#    # port 22 might not be available immediately after the instance finishes launching
#    return if retries == 2
#    retries += 1
#    sleep 1
#    retry
#  rescue Exception => e
#    puts e.message
#    puts e.backtrace.inspect
#  end
#end
#
#server_json = JSON.parse(File.read("server_data.json"), :symbolize_names => true)
#
#b = Time.now
#delta = b.to_f - a.to_f
#puts "startup time is #{delta}"
##puts send_command(server_json[:server_ip], 'nproc | tr -d "\n"', File.read("ec2_server_key.pem"))
