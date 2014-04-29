OpenStudio AWS Gem Change Log
==================================

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

### Major Changes (may be backwards incompatible)

### New Features

### Resolved Issues

* Now depends on json_pure for window users

Version 0.1.1
-------------

### Small Changes

* Updated to OpenStudio Server Version 1.1.4

### Major Changes (may be backwards incompatible)

### New Features

### Resolved Issues

Version 0.1
-----------
Initial release.



