import boto3
import json
import time
import zipfile
import os
from dotenv import load_dotenv

load_dotenv()

# AWS Clients
events_client = boto3.client("events")
lambda_client = boto3.client("lambda")
iam_client = boto3.client("iam")
s3_client = boto3.client("s3")
ssm_client = boto3.client("ssm")

# Configuration
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME")  # Ensure this bucket name is globally unique
LAMBDA_FUNCTION_NAME = os.environ.get("LAMBDA_FUNCTION_NAME")
EVENT_RULE_NAME = os.environ.get("EVENT_RULE_NAME")
AWS_REGION = os.environ.get("AWS_REGION")  # Update to your desired AWS region
CLUSTER_NAME = os.environ.get("CLUSTER_NAME")
LAMBDA_ROLE_NAME = os.environ.get("LAMBDA_ROLE_NAME")

# Step 1: Create a S3 Bucket
def create_s3_bucket():
    s3_client.create_bucket(
        Bucket=S3_BUCKET_NAME,
        CreateBucketConfiguration={'LocationConstraint': AWS_REGION}
    )

    print(f"S3 Bucket {S3_BUCKET_NAME} created.")


# Step 2: Create an Amazon EventBridge Rule
def create_eventbridge_rule():
    rule_response = events_client.put_rule(
        Name=EVENT_RULE_NAME,
        ScheduleExpression="rate(7 days)",
        State="ENABLED",
        Description="Triggers every 7 days"
    )

    rule_arn = rule_response["RuleArn"]
    print(f"EventBridge Rule Created: {rule_arn}")
    return rule_arn

# Step 3: Create a Lambda Function
def create_lambda_function():
    # IAM Role for Lambda
    role_name = LAMBDA_ROLE_NAME
    assume_role_policy = json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    })

    role = iam_client.create_role(
        RoleName=role_name,
        AssumeRolePolicyDocument=assume_role_policy
    )

    lambda_policy = json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": ["ssm:SendCommand", "ssm:GetCommandInvocation", "ec2:DescribeInstances"], "Resource": "*"},
            {"Effect": "Allow", "Action": "s3:PutObject", "Resource": f"arn:aws:s3:::{S3_BUCKET_NAME}/*"}, 
        ]
    })

    iam_client.put_role_policy(
        RoleName=role_name, PolicyName="LambdaPolicy", PolicyDocument=lambda_policy
    )

    # Lambda Function Code
    lambda_code = """\
import json
import boto3
import time
import datetime
import os


ssm_client = boto3.client("ssm")
s3_client = boto3.client("s3")


def get_eks_instance_ids(CLUSTER_NAME, tag_key="aws:eks:cluster-name"):
    ec2 = boto3.client("ec2")
    
    # Filter instances that have the specified tag and are in a running state
    filters = [
        {"Name": f"tag:{tag_key}", "Values": [CLUSTER_NAME]},
        {"Name": "instance-state-name", "Values": ["pending", "running"]}
    ]
    
    response = ec2.describe_instances(Filters=filters)
    
    instance_ids = []
    for reservation in response.get("Reservations", []):
        for instance in reservation.get("Instances", []):
            instance_ids.append(instance["InstanceId"])
    
    return instance_ids

def lambda_handler(event, context):
    
    CLUSTER_NAME = os.environ.get("CLUSTER_NAME")
    instance_ids = get_eks_instance_ids(CLUSTER_NAME)


    # Download and execute the EKS log collector script
    commands = [
        "sudo su -",
        'TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`',
        'instance_id=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)',
        'S3_BUCKET=your-s3-bucket',
        "cd /var/log",
        "rm -f eks_*",
        "cd /bin",
        "curl -O https://amazon-eks.s3.amazonaws.com/support/log-collector-script/linux/eks-log-collector.sh",
        "chmod +x eks-log-collector.sh",
        "./eks-log-collector.sh",
        "cd /var/log",
        "aws s3 cp eks_* s3://${S3_BUCKET}/eks-logs-${instance_id}.tar.gz"
    ]
    
    response = ssm_client.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=600
    )
    
    command_id = response["Command"]["CommandId"]

    # Wait for the command to complete
    time.sleep(15)

    index = 0
    for instance_id in instance_ids:
        # Check command status
        invocation = ssm_client.get_command_invocation(CommandId=command_id, InstanceId=instance_ids[index])
        

        if invocation["Status"] == "Success":
            print(f"Logs successfully collected and uploaded for instance {instance_id}.")

        else:
            print(f"Failed to collect logs for instance {instance_id}.")

        index += 1


    return {"status": "success"}

"""

    # Create a deployment package
    lambda_zip_path = "/tmp/lambda_function.zip"
    with zipfile.ZipFile(lambda_zip_path, "w") as z:
        z.writestr("lambda_function.py", lambda_code)

    with open(lambda_zip_path, "rb") as f:
        lambda_code_bytes = f.read()
    time.sleep(60)
    response = lambda_client.create_function(
        FunctionName=LAMBDA_FUNCTION_NAME,
        Runtime="python3.8",
        Role=role["Role"]["Arn"],
        Handler="lambda_function.lambda_handler",
        Code={"ZipFile": lambda_code_bytes},
        Timeout=300,
        MemorySize=256
        Environment={
            "Variables": {
                "CLUSTER_NAME": "your-cluster-name",
                "S3_BUCKET": "your-s3-bucket"
            }
    )

    print(f"Lambda Function {LAMBDA_FUNCTION_NAME} created.")
    return response["FunctionArn"]

# Step 4: Attach the Lambda Function to the EventBridge Rule
def attach_lambda_to_eventbridge(lambda_arn, rule_arn):
    events_client.put_targets(
        Rule=EVENT_RULE_NAME,
        Targets=[{"Id": "1", "Arn": lambda_arn}]
    )

    lambda_client.add_permission(
        FunctionName=LAMBDA_FUNCTION_NAME,
        StatementId="AllowEventBridgeInvoke",
        Action="lambda:InvokeFunction",
        Principal="events.amazonaws.com",
        SourceArn=rule_arn
    )

    print("Lambda function attached to EventBridge rule.")

# Run the setup functions
if __name__ == "__main__":
    create_s3_bucket()
    rule_arn = create_eventbridge_rule()
    lambda_arn = create_lambda_function()
    attach_lambda_to_eventbridge(lambda_arn, rule_arn)
