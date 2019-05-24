OpenStudio AWS Gem Change Log
==================================


Version 0.7.0
-------------
* Fix worker off by one bug
* Update Net SSH and Net SCP

Version 0.5 - 0.6
-----------------
* These releases did not include change logs

Version 0.4.2
-------------
* Fix net-ssh to 3.0.2 because newer version caused infinite loop

Version 0.4.1
-------------
* Fix the SSH Timeout Exception

Version 0.4.0
-------------
* When listing the AMI, allow future versions of OpenStudio to return the latest stable version 
* Load the key name and security groups from the AWS instance information.
* Add method on Aws to get the group_uuid 
* Load worker keys from disk (if they exist) when constructing the OpenStudioAwsWrapper class
* Have `total_instances_count` return the region and first availability zone
* Add `describe_all_instances`
* Add a stable JSON file that can be used to flag which versions of the server are stable (used by OpenStudio PAT).
* Remove all puts and replace with logger. This is required because OpenStudio PAT reads the result from the command line.
* Add the method `describe_availability_zones` to the root AWS class
* Add the method `total_instances_count` to the root AWS class
* Add method to list status of all instances in the group
* Add method to `delete_key_pair`
* Add launch time to the server data struct
* Add cloud watch class to calculate the cost
* Add save_directory to override the default path to save private keys and server configuration files
* Remove old AMIs in the AMI List (versions with 0.0.x)
* Place previous stable AMI version in the list for OpenStudio
* Remove support for Ruby 1.9. Add support for Ruby 2.1.

Version 0.3.2
-------------
* Prefer use of the access and secret key in the environment variables if defined
* Support i2 instance ephemeral storage. These instances will take a bit longer to startup because the volumes are not yet created.

Version 0.3.1
-------------
* Allow for URL redirections since the developer.nrel.gov is now on aws

Version 0.3.0
-------------
* Update aws-sdk-core-ruby to 2.0.20.
* Add VPC
* Use private ip addresses for AWS based communication
* Change single security group to an array
* Allow multiple security groups to be used
* Add method to save the cluster JSON
* Add top level terminate method to delete the machine that belong to the cluster (based on group uuid)
* Fix setting the group uuid when loading an existing cluster JSON file
* Upload public/private key for worker-node communication
* Change hosts file to use openstudio.server (not master). This will prevent older AMIs to not work with this gem'

Version 0.2.6
-------------
* Don't pass in a predefined availability zone. Make sure that the workers are placed in the server's zone.

Version 0.2.5
-------------
* Enable i3 instances on AWS for large storage

Version 0.2.4
-------------
* Allow custom instance tags when starting an instance
* Allow no workers

Version 0.2.3
-------------
* No longer support cc2 instances. The HVM instances are preferred and don't need a different cluster instance.

Version 0.2.2
-------------
* aws-sdk-core-ruby rc15 has bug for windows. Force version rc14

Version 0.2.1
-------------
* [BUG FIX] Fix issue with security groups with new AWS accounts

Version 0.2.0
-------------
* Unzip mongoid models to a model subdirectory. 
* Support user specified private keys
* Force region and availability zone to be the same
* Update launch scripts for workflow gem bundler
* Re-enable m2 generation machines because of larger volumes
* Allow uploading, shelling, and downloading from base OpenStudio::Aws Object
* Timestamp in JSON instance is now an integer (epoch time)
* GroupUUID is now an actual UUID instead of a timestamp in seconds (removes race condition when spinning up clusters in parallel)
* Changes to support upcoming aws-sdk-core version 2.0

Version 0.1.26
--------------
* Fix underscore in the port range for security groups

Version 0.1.23-25
--------------
* Delay the starting of MongoDB for 15 seconds on boot because of the pre-allocation of journals
* Code cleanup

Version 0.1.22
--------------
* Update Worker and Server Scripts to remove world writable warning

Version 0.1.21
--------------
* Test AWS Ruby API RC6
* Update pricing information

Version 0.1.20
--------------
* Always enable the true flag for the master node running as a server

Version 0.1.17/18/19
-------------------
* Fix the sorting of AMIs
* Fix default URL and point to rsrc (not server) on developer.nrel.gov

Version 0.1.16
--------------
* Fix tests
* Add option parsing to AMI list
* Better Support of Version 2 AMI listing

Version 0.1.14/15
-------------
* Add basic support for proxies for Net::SSH and Net::SCP (need to add for AWS still)
* Add AMI json list of available AMIs for version 1 & 2

Version 0.1.13
--------------
* Add defaulted argument for the name of the server_json file to create_server

Version 0.1.12
--------------
* Use HVM version when instance type is cc.* or c.*

Version 0.1.11
-------------
* AMI lookup is now defaulted.  

Version 0.1.8/9
-------------
* Use new version of AWS-SDK-Ruby (core).  Break out into several classes.

Version 0.1.7
-------------
* Bump version of aws-sdk. Package a custom gem that doesn't require JSON as a gemspec dependency

Version 0.1.6
-------------
* Update os-aws.rb script to the most recent version in OpenStudio repo

Version 0.1.4
-------------
* Package custom AWS gem locally

Version 0.1.3
-------------
* Now depends on json_pure for window users

Version 0.1.1
-------------
* Updated to OpenStudio Server Version 1.1.4

Version 0.1
-----------
Initial release.



