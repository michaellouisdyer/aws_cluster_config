#!/bin/bash

# Takes three arguments:
#   bucket name - one that has already been created
#   name of key file - without .pem extension
#   number of slave instances
#      ex. bash launch_cluster.sh mybucket mypem 2

# This script assumes that the file bootstrap-emr.sh is
#   in your current directory.

# Requires the awscli to be set up, need to have correct default region configured
# Run `aws configure` to set this up

# require for first time cluster creators.
# you can comment this out if you are sure
# that the default emr roles already exist
aws emr create-default-roles

aws s3 cp emr-config.sh s3://$1/scripts/emr-config.sh

aws emr create-cluster \
    --enable-debugging \
    --log-uri s3://$1/new_logm4 \
    --name PySparkCluster \
    --release-label emr-5.16.0 \
    --applications Name=Spark Name=Ganglia \
    --ec2-attributes KeyName=$2,SubnetIds=subnet-0dc89157 \
    --use-default-roles \
    --instance-groups \
      InstanceGroupType=MASTER,InstanceCount=1,InstanceType=c3.2xlarge \
      InstanceGroupType=CORE,InstanceCount=$3,InstanceType=c3.2xlarge \
    --bootstrap-actions Path=s3://$1/scripts/emr-config.sh
