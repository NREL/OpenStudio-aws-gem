require 'spec_helper'

SERVER_AMI = 'ami-e0b38888'
WORKER_AMI = 'ami-a8bc87c0'

describe OpenStudio::Aws::Aws do
  context 'create a new instance' do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new

      @group_id = nil

      FileUtils.rm_f 'ec2_server_key.pem' if File.exist? 'ec2_server_key.pem'
      FileUtils.rm_f 'server_data.json' if File.exist? 'server_data.json'
    end

    it 'should create a new instance' do
      expect(@aws.os_aws.server).to be_nil
      expect(@aws.os_aws.workers).to be_empty
    end

    it 'should create a server' do
      options = { instance_type: 'm3.medium', image_id: SERVER_AMI }

      FileUtils.rm_f 'ec2_server_key.pem' if File.exist? 'ec2_server_key.pem'
      FileUtils.rm_f 'server_data.json' if File.exist? 'server_data.json'

      @aws.create_server(options)

      @aws.save_cluster_info 'server_data.json'

      expect(File.exist?('ec2_server_key.pem')).to be true
      expect(File.exist?('server_data.json')).to be true
      expect(File.exist?('ec2_worker_key.pem')).to be true
      expect(File.exist?('ec2_worker_key.pub')).to be true
      expect(@aws.os_aws.server).not_to be_nil
      expect(@aws.os_aws.server.data.availability_zone).to match /us-east-../

      h = @aws.os_aws.server.to_os_hash
      expect(h[:group_id]).to be_a String
      expect(h[:group_id]).to match /^[\d\S]{32}$/
      expect(h[:location]).to eq 'AWS'

      @group_id = h[:group_id]
    end

    it 'should create a 1 worker' do
      options = { instance_type: 'm3.medium', image_id: WORKER_AMI }

      @aws.create_workers(1, options)

      expect(@aws.os_aws.workers.size).to eq 1
      expect(@aws.os_aws.workers[0].data[:dns]).not_to be_nil
      expect(@aws.os_aws.server.data.availability_zone).to eq @aws.os_aws.workers[0].data.availability_zone
    end

    it 'should be able to connect a worker to an existing server' do
      options = { instance_type: 'm3.medium', image_id: WORKER_AMI }

      # will require a new @aws class--but attached to same group_uuid
      @config = OpenStudio::Aws::Config.new
      @aws_2 = OpenStudio::Aws::Aws.new

      @aws_2.os_aws.find_server(@aws.os_aws.server.to_os_hash)

      expect(@aws.os_aws.server).not_to be_nil
    end

    after :all do
      if File.exist? 'server_data.json'
        j = JSON.parse(File.read('server_data.json'), symbolize_names: true)

        @aws.terminate_instances_by_group_id(j[:group_id])
      end
    end
  end

  context 'upload data to a server' do
    before :all do
      @group_id = nil

      config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should create a server' do
      options = {
        instance_type: 'm3.medium',
        image_id: SERVER_AMI
      }

      @aws.create_server(options)
      @aws.create_workers(0, options)

      @aws.save_cluster_info 'server_data.json'

      h = @aws.os_aws.server.to_os_hash
      expect(h[:group_id]).to be_a String
      expect(h[:group_id]).to match /^[\d\S]{32}$/
      @group_id = h[:group_id]
    end

    it 'should upload a file after loading the existing server' do
      expect(File.exist?('server_data.json')).to be true

      j = JSON.parse(File.read('server_data.json'), symbolize_names: true)

      config = OpenStudio::Aws::Config.new
      aws2 = OpenStudio::Aws::Aws.new

      aws2.load_instance_info_from_file('server_data.json')

      expect(aws2.os_aws.server.group_uuid).to eq j[:group_id]

      local_file = File.expand_path('spec/resources/upload_me.sh')
      remote_file = '/home/ubuntu/i_uploaded_this_file.sh'

      aws2.upload_file(:server, local_file, remote_file)

      aws2.shell_command(:server, "source #{remote_file}")

      FileUtils.rm_f 'success.receipt' if File.exist? 'success.receipt'
      aws2.download_remote_file(:server, '/home/ubuntu/success.receipt', 'success.receipt')
      expect(File.exist?('success.receipt')).to be true

      FileUtils.rm_f 'gemlist.receipt' if File.exist? 'gemlist.receipt'
      aws2.download_remote_file(:server, '/home/ubuntu/gemlist.receipt', 'gemlist.receipt')
      expect(File.exist?('gemlist.receipt')).to be true
      gemlist = File.read('gemlist.receipt')
      expect(gemlist).to match /^s3 \(.*\)$/
    end

    after :all do
      if File.exist? 'server_data.json'
        j = JSON.parse(File.read('server_data.json'), symbolize_names: true)

        @aws.terminate_instances_by_group_id(j[:group_id])
      end
    end
  end

  context 'workers before server' do
    before(:all) do
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should not create any workers' do
      expect { @aws.create_workers(5) }.to raise_error
    end
  end

  context 'create aws tags' do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new

      @group_id = nil
    end

    it 'should create a server with tags' do
      begin
        options = {
          instance_type: 'm3.medium',
          image_id: SERVER_AMI,
          tags: [
            'ci_tests=true',
            'nothing=else',
            'this=is the end    ',
            'this=   is the beginning   '
          ]
        }

        test_pem_file = 'ec2_server_key.pem'
        FileUtils.rm_f test_pem_file if File.exist? test_pem_file
        FileUtils.rm_f 'server_data.json' if File.exist? 'server_data.json'

        @aws.create_server(options)

        @aws.save_cluster_info 'server_data.json'

        expect(File.exist?('ec2_server_key.pem')).to be true
        expect(File.exist?('server_data.json')).to be true
        expect(@aws.os_aws.server).not_to be_nil

        h = @aws.os_aws.server.to_os_hash
        expect(h[:group_id]).to be_a String
        expect(h[:group_id]).to match /^[\d\S]{32}$/
        expect(h[:location]).to eq 'AWS'

        @group_id = h[:group_id]
      ensure
        @aws.terminate_instances_by_group_id(h[:group_id])
      end
    end
  end

  context 'server only' do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new

      @group_id = nil
    end

    it 'should allow a zero length worker' do
      begin
        options = {
          instance_type: 'm3.medium',
          image_id: SERVER_AMI,
          tags: [
            'ci_tests=true',
            'ServerOnly=true'
          ]
        }

        expect { @aws.create_workers(0) }.to raise_error "Can't create workers without a server instance running"

        test_pem_file = 'ec2_server_key.pem'
        FileUtils.rm_f test_pem_file if File.exist? test_pem_file
        FileUtils.rm_f 'server_data.json' if File.exist? 'server_data.json'

        @aws.create_server(options)

        # Still have to call "create workers" or the configuration won't happen.
        @aws.create_workers(0, options)

        h = @aws.os_aws.server.to_os_hash
        expect(h[:group_id]).to be_a String
        expect(h[:group_id]).to match /^[\d\S]{32}$/
        expect(h[:location]).to eq 'AWS'
      ensure
        @aws.terminate_instances_by_group_id(h[:group_id])
      end
    end
  end

  context 'key locations' do
    before :all do
      FileUtils.rm_rf 'spec/output/save_path'

      @config = OpenStudio::Aws::Config.new
      options = {
        save_directory: 'spec/output/save_path'
      }
      @aws = OpenStudio::Aws::Aws.new(options)

      @group_id = nil
    end

    it 'should allow a different location for saving aws config files' do
      begin
        options = {
          instance_type: 'm3.medium',
          image_id: SERVER_AMI
        }

        expect(@aws.save_directory).to eq File.join(File.expand_path('.'), 'spec/output/save_path')

        @aws.create_server(options)

        @aws.save_cluster_info "#{@aws.save_directory}/server_data.json"

        expect(File.exist?('spec/output/save_path/ec2_server_key.pem')).to be true
        expect(File.exist?('spec/output/save_path/ec2_worker_key.pem')).to be true
        expect(File.exist?('spec/output/save_path/ec2_worker_key.pub')).to be true
        expect(File.exist?('spec/output/save_path/server_data.json')).to be true

        expect(@aws.os_aws.server).not_to be_nil
        expect(@aws.os_aws.server.data.availability_zone).to match /us-east-../

        h = @aws.os_aws.server.to_os_hash
        expect(h[:group_id]).to be_a String
        expect(h[:group_id]).to match /^[\d\S]{32}$/
        @group_id = h[:group_id]
      ensure
        @aws.terminate_instances_by_group_id(@group_id)
      end

      # verify that the instances are dead -- how?
    end

    it 'should load in the worker keys if exist on disk' do
      options = {
        save_directory: 'spec/output/save_path'
      }
      @aws_2 = OpenStudio::Aws::Aws.new(options)

      expect(@aws_2.os_aws.worker_keys.private_key).not_to be_nil
      expect(@aws_2.os_aws.worker_keys.public_key).not_to be_nil
    end
  end

  context 'stateful creation of server and worker' do
    before(:all) do
      @config = OpenStudio::Aws::Config.new
      @aws = OpenStudio::Aws::Aws.new
    end

    it 'should create the server and save the state' do
      options = {
        instance_type: 'm3.medium',
        image_id: SERVER_AMI,
        tags: [
          'ci_tests=true',
          'ServerOnly=true'
        ]
      }

      test_pem_file = 'ec2_server_key.pem'
      FileUtils.rm_f test_pem_file if File.exist? test_pem_file
      FileUtils.rm_f 'server_data.json' if File.exist? 'server_data.json'

      @aws.create_server(options)
      @aws.save_cluster_info 'server_data.json'

      h = @aws.os_aws.server.to_os_hash
      expect(h[:group_id]).to be_a String
      expect(h[:group_id]).to match /^[\d\S]{32}$/
      expect(h[:location]).to eq 'AWS'
    end

    it 'should load server information from json and launch worker' do
      aws2 = OpenStudio::Aws::Aws.new
      aws2.load_instance_info_from_file('server_data.json')

      options = {
        instance_type: 'm3.medium',
        image_id: WORKER_AMI
      }

      aws2.create_workers(1, options)
      aws2.save_cluster_info 'server_data.json'

      expect(File.exist?('server_data.json')).to eq true
      # check if file exists

      h = aws2.cluster_info # to make sure that the settings are correct
      expect(h[:server][:worker_private_key_file_name]).to match /.*ec2_worker_key.pem/
      expect(h[:workers].size).to eq 1
    end

    after :all do
      @aws.terminate
    end
  end
end
