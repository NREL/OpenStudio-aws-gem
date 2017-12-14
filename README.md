OpenStudio AWS Gem
==================

[![Build Status](https://travis-ci.org/NREL/OpenStudio-aws-gem.svg?branch=develop)](https://travis-ci.org/NREL/OpenStudio-aws-gem) [![Dependency Status](https://www.versioneye.com/user/projects/540a30dbccc023fe760002c9/badge.svg?style=flat)](https://www.versioneye.com/user/projects/540a30dbccc023fe760002c9)

OpenStudio AWS uses the OpenStudio AWS ruby class to launch a server and multiple workers for doing 
OpenStudio/EnergyPlus Analyses using Amazon AWS/EC2

Instructions
------------

Typically this gem is used in conjunction with other gems such as OpenStudio-Analysis.

To use this make sure to have ruby 2.0 in your path.

Development Notes
-----------------

**Do not test this gem with credentials to a production account.** The networking layer is extensively tested and requires that no OpenStudio AWS VPC-related objects exist in your account. Should they exist tests will fail, and your settings may be deleted based on testing order. As such we recommend creating a separate IAM for testing this gem, and removing all VPC and EC2 object created after execution of the tests. No objects are known to exist following running the tests, however this should always be confirmed. If you find leftover objects following a test, please open an issue on the OpenStudio repo issue tracker, and better yet, send us a PR!

There is an underlying attempt to merge several OpenStudio based gems into one and have a general 
OpenStudio namespace for ruby classes.

The AWS SDK gem is custom built and distributed with this gem in order to remove the JSON dependency.  If you are running ruby 1.9 or greater, then JSON is installed in the std lib and should be called out in the gemspec.
