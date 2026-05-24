"""
Local test script for the Lambda handler.
Run this to verify formatting logic without deploying to AWS.

Usage:
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    python tests/test_handler_local.py
"""

import json
import os
import sys

# Add lambda source to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "terraform", "modules", "lambda-formatter", "src"))

from unittest.mock import patch, MagicMock

# Mock boto3 before importing handler
mock_ec2 = MagicMock()
mock_ec2.describe_tags.return_value = {
    "Tags": [
        {"Key": "karpenter.sh/nodepool", "Value": "default"},
        {"Key": "karpenter.sh/nodeclaim", "Value": "default-abc123"},
        {"Key": "karpenter.sh/capacity-type", "Value": "on-demand"},
        {"Key": "node.kubernetes.io/instance-type", "Value": "m5.xlarge"},
        {"Key": "kubernetes.io/cluster/production-eks", "Value": "owned"},
    ]
}


def get_mock_client(*args, **kwargs):
    return mock_ec2


# Sample events
ECS_RETIREMENT_EVENT = {
    "version": "0",
    "id": "12345678-1234-1234-1234-123456789012",
    "detail-type": "AWS Health Event",
    "source": "aws.health",
    "account": "123456789012",
    "time": "2026-05-24T10:00:00Z",
    "region": "us-east-1",
    "detail": {
        "service": "ECS",
        "eventTypeCategory": "scheduledChange",
        "eventTypeCode": "AWS_ECS_TASK_PATCHING_RETIREMENT",
        "affectedEntities": [
            {"entityValue": "arn:aws:ecs:us-east-1:123456789012:task/prod/a1b2c3d4"},
            {"entityValue": "arn:aws:ecs:us-east-1:123456789012:service/prod/api"},
        ],
    },
}

EC2_TERMINATED_EVENT = {
    "version": "0",
    "id": "12345678-1234-1234-1234-123456789013",
    "detail-type": "EC2 Instance State-change Notification",
    "source": "aws.ec2",
    "account": "123456789012",
    "time": "2026-05-24T10:05:00Z",
    "region": "us-east-1",
    "detail": {
        "instance-id": "i-0abc123def456789a",
        "state": "terminated",
    },
}

EKS_POD_TERMINATION_EVENT = {
    "version": "0",
    "id": "12345678-1234-1234-1234-123456789014",
    "detail-type": "EKS Fargate Pod Scheduled Termination",
    "source": "aws.eks",
    "account": "123456789012",
    "time": "2026-05-24T10:10:00Z",
    "region": "us-east-1",
    "detail": {
        "clusterName": "production-eks",
        "fargateProfileName": "default",
        "podName": "api-server-7b9f4c6d8-x2k4m",
        "namespace": "production",
    },
}

EC2_MAINTENANCE_EVENT = {
    "version": "0",
    "id": "12345678-1234-1234-1234-123456789015",
    "detail-type": "AWS Health Event",
    "source": "aws.health",
    "account": "123456789012",
    "time": "2026-05-24T10:15:00Z",
    "region": "us-east-1",
    "detail": {
        "service": "EC2",
        "eventTypeCategory": "scheduledChange",
        "eventTypeCode": "AWS_EC2_SYSTEM_MAINTENANCE_EVENT",
        "affectedEntities": [
            {"entityValue": "i-0abc123def456789a"},
            {"entityValue": "i-0def456abc789012b"},
        ],
    },
}


def main():
    """Run all test events and print formatted output."""
    # Set a dummy webhook URL if not set (will print instead of posting)
    if not os.environ.get("SLACK_WEBHOOK_URL"):
        os.environ["SLACK_WEBHOOK_URL"] = ""
        print("⚠️  SLACK_WEBHOOK_URL not set — will print messages instead of posting\n")

    with patch("boto3.client", side_effect=get_mock_client):
        import handler

        # Override post_to_slack to just print
        original_post = handler.post_to_slack

        def mock_post(message):
            if message:
                print(json.dumps(message, indent=2))
                print()
            else:
                print("  [No message — event filtered out]\n")

        handler.post_to_slack = mock_post

        test_cases = [
            ("ECS Fargate Task Retirement", ECS_RETIREMENT_EVENT),
            ("EC2 Instance Terminated (Karpenter Node)", EC2_TERMINATED_EVENT),
            ("EKS Fargate Pod Scheduled Termination", EKS_POD_TERMINATION_EVENT),
            ("EC2 Scheduled Maintenance", EC2_MAINTENANCE_EVENT),
        ]

        for name, event in test_cases:
            print(f"{'='*60}")
            print(f"TEST: {name}")
            print(f"{'='*60}")
            handler.lambda_handler(event, None)
            print()

        handler.post_to_slack = original_post

    print("✅ All test events processed successfully")


if __name__ == "__main__":
    main()
