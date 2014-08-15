OpenStudio AWS Gem Change Log
==================================

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

Version 0.1.26
--------------
* Fix underscore in the port range for security groups

Version 0.1.23-25
--------------
* Delay the starting of MongoDB for 15 seconds on boot because of the preallocation of journals
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



