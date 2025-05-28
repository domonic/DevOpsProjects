#!/bin/bash
set -euo pipefail

VPC_ID="$1"

if [[ -z "$VPC_ID" ]]; then
  echo "Usage: $0 <vpc-id>"
  exit 1
fi

echo "Cleaning up VPC: $VPC_ID"

# 1. Detach and delete Internet Gateways
for igw in $(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query 'InternetGateways[].InternetGatewayId' --output text); do
  echo "Detaching and deleting Internet Gateway: $igw"
  aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
  aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
done

# 2. Delete NAT Gateways
for nat in $(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --query 'NatGateways[].NatGatewayId' --output text); do
  echo "Deleting NAT Gateway: $nat"
  aws ec2 delete-nat-gateway --nat-gateway-id "$nat"
  sleep 5
done

# 3. Delete Network Interfaces
for eni in $(aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC_ID --query 'NetworkInterfaces[].NetworkInterfaceId' --output text); do
  echo "Deleting ENI: $eni"
  aws ec2 delete-network-interface --network-interface-id "$eni"
done

# 4. Delete route tables (except main)
for rtb in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query 'RouteTables[].RouteTableId' --output text); do
  if [[ $(aws ec2 describe-route-tables --route-table-ids $rtb --query 'RouteTables[0].Associations[?Main==`true`]') == "[]" ]]; then
    echo "Deleting Route Table: $rtb"
    aws ec2 delete-route-table --route-table-id "$rtb"
  fi
done

# 5. Delete Security Groups (except default)
for sg in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
  echo "Deleting Security Group: $sg"
  aws ec2 delete-security-group --group-id "$sg"
done

# 6. Delete Subnets
for subnet in $(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].SubnetId' --output text); do
  echo "Deleting Subnet: $subnet"
  aws ec2 delete-subnet --subnet-id "$subnet"
done

# 7. Delete VPC Endpoints
for ep in $(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID --query 'VpcEndpoints[].VpcEndpointId' --output text); do
  echo "Deleting VPC Endpoint: $ep"
  aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep"
done

# 8. Delete the VPC
echo "Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id "$VPC_ID"

echo "✅ VPC $VPC_ID and all its dependencies have been deleted."

