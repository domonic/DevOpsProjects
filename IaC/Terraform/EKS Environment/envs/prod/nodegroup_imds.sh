#!/bin/bash

set -e

# ========= USER CONFIGURATION ==========
NODEGROUP_GREEN="k8s-prod-eks-node-group-green"
NODEGROUP_BLUE="k8s-prod-eks-node-group-blue"
REGION="us-west-2"
# =======================================



for id in $(aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=$NODEGROUP_GREEN" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text)
do
  aws ec2 modify-instance-metadata-options --instance-id $id --http-put-response-hop-limit 2 --http-endpoint enabled
done


for id in $(aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=$NODEGROUP_BLUE" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text)
do
  aws ec2 modify-instance-metadata-options --instance-id $id --http-put-response-hop-limit 2 --http-endpoint enabled
done