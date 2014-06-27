#!/bin/sh

# NOTE: This file is now the main script -- OpenStudio's version is now out of date

# AWS Server Bootstrap File
# This script is used to configure the AWS boxes

# Change Host File Entries
ENTRY="localhost localhost master"
FILE=/etc/hosts
if grep -q "$ENTRY" $FILE; then
  echo "entry already exists"
else
  sudo sh -c "echo $ENTRY >> /etc/hosts"
fi

# copy all the setup scripts to the appropriate home directory
# the scripts are called by the AWS connector for passwordless ssh config
cp /data/launch-instance/setup* /home/ubuntu/
chmod 775 /home/ubuntu/setup*
chown ubuntu:ubuntu /home/ubuntu/setup*

# stop the various services that use mongo
sudo service delayed_job stop
sudo service apache2 stop
sudo service mongodb stop

# remove mongo db & add it back
sudo mkdir -p /mnt/mongodb/data
sudo chown mongodb:nogroup /mnt/mongodb/data
sudo rm -rf /var/lib/mongodb

# restart mongo
sudo service mongodb start
# delay the continuation because mongo is a forked process and when it initializes
# it has to create the preallocated journal files (takes ~ 90 seconds on a slower system)
sleep 2m

# restart the rails application
sudo service apache2 stop
sudo service apache2 start

# Add in the database indexes after making the db directory
sudo chmod 777 /var/www/rails/openstudio/public
cd /var/www/rails/openstudio
rake db:purge
rake db:mongoid:create_indexes

## Worker Data Configuration -- On Vagrant this is a separate file

# Force the generation of various directories that are in the EBS mnt
sudo rm -rf /mnt/openstudio
sudo mkdir -p /mnt/openstudio
sudo chown -R ubuntu:www-data /mnt/openstudio
sudo chmod -R 775 /mnt/openstudio

# save application files into the right directory
sudo cp -rf /data/worker-nodes/* /mnt/openstudio/

# install workflow dependencies
cd /mnt/openstudio
sudo rm -f Gemfile.lock
bundle update
sudo bundle update

# copy over the models needed for mongo
cd /mnt/openstudio/rails-models && sudo unzip -o rails-models.zip -d models

# rerun the permissions after unzipping the files
sudo chown -R ubuntu:www-data /mnt/openstudio
sudo find /mnt/openstudio -type d -print0 | xargs -0 chmod 775
sudo find /mnt/openstudio -type f -print0 | xargs -0 chmod 664

## End Worker Data Configuration

# restart rserve
sudo service Rserve restart

# restart delayed jobs
sudo service delayed_job start

#file flag the user_data has completed
cat /dev/null > /home/ubuntu/user_data_done


