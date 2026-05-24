"""
AWS Infrastructure Lifecycle Alerts — Lambda Formatter

Handles events from:
- AWS Health (ECS Fargate task retirement, EC2 scheduled maintenance)
- EC2 Instance State Changes (Karpenter / EKS Auto Mode node terminations)
- EKS Service Events (Fargate pod scheduled termination)

Enriches EC2 events with instance tags to identify Karpenter/Auto Mode nodes,
then posts formatted messages to Slack via Incoming Webhook.
"""

import json
import logging
import os

import boto3
from botocore.config import Config
import urllib3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

http = urllib3.PoolManager()

SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")
SLACK_CHANNEL = os.environ.get("SLACK_CHANNEL", "infra-alerts")

ec2_client = boto3.client("ec2", config=Config(connect_timeout=5, read_timeout=10, retries={"max_attempts": 2}))


def lambda_handler(event, context):
    """Main entry point for EventBridge events."""
    logger.info("Received event: %s", json.dumps(event, default=str))

    source = event.get("source", "")
    detail_type = event.get("detail-type", "")
    detail = event.get("detail", {})

    message = None

    if source == "aws.health":
        service = detail.get("service", "")
        if service == "ECS":
            message = format_ecs_retirement(event)
        elif service == "EC2":
            message = format_ec2_maintenance(event)
        else:
            message = format_health_generic(event)

    elif source == "aws.ec2" and detail_type == "EC2 Instance State-change Notification":
        message = format_instance_termination(event)

    elif source == "aws.eks":
        message = format_eks_event(event)

    else:
        logger.warning("Unhandled event source: %s / %s", source, detail_type)
        message = format_generic(event)

    if message:
        post_to_slack(message)


    return {"statusCode": 200, "body": "OK"}


# -----------------------------------------------------------------------------
# Formatters
# -----------------------------------------------------------------------------


def format_ecs_retirement(event):
    """Format ECS Fargate task retirement notification."""
    detail = event.get("detail", {})
    affected = detail.get("affectedEntities", [])
    task_arns = [e.get("entityValue", "unknown") for e in affected]
    event_type_code = detail.get("eventTypeCode", "UNKNOWN")
    region = event.get("region", "N/A")
    account = event.get("account", "N/A")
    event_time = event.get("time", "N/A")

    # Build task list (truncate if too many)
    if len(task_arns) > 10:
        task_list = "\n".join(f"• `{t}`" for t in task_arns[:10])
        task_list += f"\n• _...and {len(task_arns) - 10} more_"
    else:
        task_list = "\n".join(f"• `{t}`" for t in task_arns) if task_arns else "• No specific tasks listed"

    return {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "⚠️ ECS Fargate Task Retirement Scheduled",
                    "emoji": True,
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": (
                        f"*Event:* `{event_type_code}`\n"
                        f"*Region:* `{region}`\n"
                        f"*Account:* `{account}`\n"
                        f"*Time:* `{event_time}`"
                    ),
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Affected Tasks/Services:*\n{task_list}",
                },
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": "💡 Tasks will be retired after the configured wait period. Consider redeploying proactively.",
                    }
                ],
            },
            {"type": "divider"},
        ]
    }


def format_ec2_maintenance(event):
    """Format EC2 scheduled maintenance health event."""
    detail = event.get("detail", {})
    affected = detail.get("affectedEntities", [])
    instance_ids = [e.get("entityValue", "unknown") for e in affected]
    event_type_code = detail.get("eventTypeCode", "UNKNOWN")
    region = event.get("region", "N/A")
    account = event.get("account", "N/A")
    event_time = event.get("time", "N/A")

    instance_list = "\n".join(f"• `{i}`" for i in instance_ids) if instance_ids else "• No specific instances listed"

    return {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "🔧 EC2 Scheduled Maintenance",
                    "emoji": True,
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": (
                        f"*Event:* `{event_type_code}`\n"
                        f"*Region:* `{region}`\n"
                        f"*Account:* `{account}`\n"
                        f"*Time:* `{event_time}`"
                    ),
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Affected Instances:*\n{instance_list}",
                },
            },
            {"type": "divider"},
        ]
    }


def _resolve_eks_cluster(tags):
    """Resolve EKS cluster name from instance tags."""
    cluster = tags.get("aws:eks:cluster-name", tags.get("kubernetes.io/cluster-name", ""))
    if cluster:
        return cluster
    for key in tags:
        if key.startswith("kubernetes.io/cluster/"):
            return key.split("/")[-1]
    return ""


def _classify_node(tags):
    """
    Classify an EC2 instance as Karpenter, EKS, or unmanaged based on tags.
    Returns (emoji, source_label, extra_fields) or None if not a managed K8s node.
    """
    node_pool = tags.get("karpenter.sh/nodepool", "")
    node_claim = tags.get("karpenter.sh/nodeclaim", "")
    capacity_type = tags.get("karpenter.sh/capacity-type", "")
    nodegroup = tags.get("eks:nodegroup-name", "")
    eks_cluster = _resolve_eks_cluster(tags)

    if node_pool:
        return "🔄", "Karpenter", [
            {"type": "mrkdwn", "text": f"*NodePool:*\n`{node_pool}`"},
            {"type": "mrkdwn", "text": f"*NodeClaim:*\n`{node_claim or 'N/A'}`"},
            {"type": "mrkdwn", "text": f"*Capacity:*\n`{capacity_type or 'N/A'}`"},
        ]

    if nodegroup or eks_cluster:
        label = f"EKS ({nodegroup})" if nodegroup else "EKS Auto Mode"
        return "🤖", label, [
            {"type": "mrkdwn", "text": f"*Node Group:*\n`{nodegroup or 'Auto Mode'}`"},
        ]

    return None


def format_instance_termination(event):
    """
    Format EC2 instance termination event.
    Enriches with tags to determine if Karpenter or EKS Auto Mode node.
    Returns None if the instance is not a managed K8s node (to avoid noise).
    """
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id", "unknown")
    state = detail.get("state", "unknown")
    region = event.get("region", "N/A")
    account = event.get("account", "N/A")
    event_time = event.get("time", "N/A")

    # Enrich with EC2 tags
    tags = get_instance_tags(instance_id, region)

    # Classify the node — returns None for non-K8s instances
    classification = _classify_node(tags)
    if classification is None:
        logger.info(
            "Instance %s terminated but has no K8s tags — skipping notification",
            instance_id,
        )
        return None

    emoji, source_label, extra_fields = classification
    instance_type = tags.get("node.kubernetes.io/instance-type", "N/A")
    eks_cluster = _resolve_eks_cluster(tags) or "N/A"

    fields = [
        {"type": "mrkdwn", "text": f"*Instance:*\n`{instance_id}`"},
        {"type": "mrkdwn", "text": f"*State:*\n`{state}`"},
        {"type": "mrkdwn", "text": f"*Instance Type:*\n`{instance_type}`"},
        {"type": "mrkdwn", "text": f"*Cluster:*\n`{eks_cluster}`"},
    ] + extra_fields

    return {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{emoji} Node Terminated — {source_label}",
                    "emoji": True,
                },
            },
            {"type": "section", "fields": fields},
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"Region: `{region}` | Account: `{account}` | Time: `{event_time}`",
                    }
                ],
            },
            {"type": "divider"},
        ]
    }


def format_eks_event(event):
    """Format EKS service events (Fargate pod termination, etc.)."""
    detail = event.get("detail", {})
    detail_type = event.get("detail-type", "Unknown EKS Event")
    region = event.get("region", "N/A")
    account = event.get("account", "N/A")
    event_time = event.get("time", "N/A")

    cluster_name = detail.get("clusterName", detail.get("cluster-name", "N/A"))
    fargate_profile = detail.get("fargateProfileName", "N/A")
    pod_name = detail.get("podName", "N/A")
    namespace = detail.get("namespace", "N/A")

    return {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"☸️ {detail_type}",
                    "emoji": True,
                },
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Cluster:*\n`{cluster_name}`"},
                    {"type": "mrkdwn", "text": f"*Fargate Profile:*\n`{fargate_profile}`"},
                    {"type": "mrkdwn", "text": f"*Pod:*\n`{namespace}/{pod_name}`"},
                    {"type": "mrkdwn", "text": f"*Region:*\n`{region}`"},
                ],
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"Account: `{account}` | Time: `{event_time}`",
                    }
                ],
            },
            {"type": "divider"},
        ]
    }


def format_health_generic(event):
    """Format generic AWS Health events."""
    detail = event.get("detail", {})
    service = detail.get("service", "Unknown")
    event_type_code = detail.get("eventTypeCode", "UNKNOWN")
    region = event.get("region", "N/A")
    account = event.get("account", "N/A")

    return {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"🏥 AWS Health Event — {service}",
                    "emoji": True,
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": (
                        f"*Service:* `{service}`\n"
                        f"*Event:* `{event_type_code}`\n"
                        f"*Region:* `{region}`\n"
                        f"*Account:* `{account}`"
                    ),
                },
            },
            {"type": "divider"},
        ]
    }


def format_generic(event):
    """Format any unhandled event type."""
    truncated = json.dumps(event, indent=2, default=str)[:1500]
    return {
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Unhandled Infrastructure Event:*\n```{truncated}```",
                },
            },
            {"type": "divider"},
        ]
    }


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------


def get_instance_tags(instance_id, region):  # noqa: ARG001
    """
    Fetch tags for an EC2 instance.
    Returns a dict of tag key -> value.
    Note: Tags may not be available for terminated instances after a short window.
    The region parameter is kept for interface compatibility but the module-level
    client uses the Lambda's configured region (AWS_REGION env var).
    """
    try:
        response = ec2_client.describe_tags(
            Filters=[{"Name": "resource-id", "Values": [instance_id]}]
        )
        return {tag["Key"]: tag["Value"] for tag in response.get("Tags", [])}
    except Exception as e:
        logger.warning("Failed to fetch tags for %s: %s", instance_id, str(e))
        return {}


def post_to_slack(message):
    """Post a Block Kit message to Slack via Incoming Webhook."""
    if not SLACK_WEBHOOK_URL:
        logger.error("SLACK_WEBHOOK_URL not configured — skipping notification")
        return

    payload = json.dumps(message)
    logger.info("Posting to Slack: %s", payload[:500])

    try:
        response = http.request(
            "POST",
            SLACK_WEBHOOK_URL,
            body=payload.encode("utf-8"),
            headers={"Content-Type": "application/json"},
            timeout=urllib3.Timeout(connect=5.0, read=10.0),
        )
        if response.status != 200:
            logger.error(
                "Slack webhook returned %d: %s",
                response.status,
                response.data.decode("utf-8"),
            )
    except Exception:
        logger.exception("Failed to post to Slack")
