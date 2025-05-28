#!/bin/bash

# --------- Configuration ---------
REGION="us-east-1"
AMI_ID="ami-xxxxxxxxxxxxxxxxx"  # Replace with valid RHEL 9 AMI ID
KEY_NAME="your-keypair-name"    # Replace with your existing key pair name
SECURITY_GROUP_NAME="rhcsa-rhce-lab-sg"
TAG="RHCSA-Lab"
CONTROL_INSTANCE_TYPE="t3.small"
NODE_INSTANCE_TYPE="t3.micro"
# ---------------------------------

echo "[*] Creating security group..."
aws ec2 create-security-group \
  --group-name "$SECURITY_GROUP_NAME" \
  --description "RHCSA/RHCE Lab SG" \
  --region "$REGION" 2>/dev/null

SG_ID=$(aws ec2 describe-security-groups \
  --group-names "$SECURITY_GROUP_NAME" \
  --query "SecurityGroups[0].GroupId" --output text)

echo "[*] Authorizing SSH and internal traffic..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" --protocol -1 --source-group "$SG_ID"

# Function to launch instance
launch_instance() {
  local NAME=$1
  local TYPE=$2
  echo "[*] Launching $NAME..."
  aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Lab,Value=$TAG}]" \
    --region "$REGION" >/dev/null
}

# Launch instances
launch_instance "control-node" "$CONTROL_INSTANCE_TYPE"
launch_instance "node1" "$NODE_INSTANCE_TYPE"
launch_instance "node2" "$NODE_INSTANCE_TYPE"

echo "[*] Waiting for instances to initialize..."
sleep 30

echo "[*] Fetching public IPs..."
aws ec2 describe-instances \
  --filters "Name=tag:Lab,Values=$TAG" \
  --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,IP:PublicIpAddress}" \
  --output table