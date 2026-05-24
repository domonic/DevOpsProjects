# AWS Infrastructure Lifecycle Alerts

Never miss an infrastructure maintenance event again. This project is an automated notification pipeline that captures AWS infrastructure lifecycle events and delivers formatted alerts directly to Slack — no more logging into the AWS console to check for scheduled retirements, node terminations, or maintenance windows.

## What This Does

This pipeline monitors and alerts on three categories of infrastructure events that are commonly missed in production Kubernetes and container environments:

1. **ECS Fargate Task Retirement** — When AWS retires a Fargate platform version revision (security patches, runtime updates), your running tasks will be stopped. This pipeline gives you advance notice so you can redeploy on your own schedule.

2. **Karpenter Node Termination** — When Karpenter terminates EC2 instances due to `expireAfter` TTL, drift detection (AMI changes, config updates), consolidation (cost optimization), or Spot interruptions. The pipeline identifies Karpenter-managed nodes by their tags and includes NodePool, NodeClaim, capacity type, and cluster context.

3. **EKS Auto Mode Node Lifecycle** — When EKS Auto Mode (which uses Karpenter under the hood) replaces nodes due to health issues, scheduled maintenance, or scaling decisions. Also captures EKS Fargate pod scheduled terminations.

## Why This Exists

In production environments running EKS with Karpenter or Auto Mode, and ECS Fargate services, nodes and tasks are constantly being recycled. Without visibility into these events:

- Fargate task retirements can cause unexpected service restarts
- Karpenter `expireAfter` triggers can terminate nodes running long-lived workloads
- Drift-based replacements after AMI updates can cascade across your fleet
- Spot interruptions give you only 2 minutes of warning
- EKS Auto Mode node repairs happen silently

This pipeline ensures your platform/SRE team sees every lifecycle event in real-time, with enough context to understand what happened and why.

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          EVENT SOURCES                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ AWS Health       │  │ EC2 Instance     │  │ EKS Service Events       │  │
│  │ Dashboard        │  │ State Changes    │  │                          │  │
│  │                  │  │                  │  │ • Fargate Pod Scheduled  │  │
│  │ • ECS Task       │  │ • terminated     │  │   Termination            │  │
│  │   Retirement     │  │ • shutting-down  │  │                          │  │
│  │ • EC2 Scheduled  │  │                  │  │                          │  │
│  │   Maintenance    │  │                  │  │                          │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────────┬─────────────┘  │
│           │                     │                          │                │
└───────────┼─────────────────────┼──────────────────────────┼────────────────┘
            │                     │                          │
            ▼                     ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AMAZON EVENTBRIDGE                                        │
│                                                                             │
│  Rule 1: aws.health → ECS task retirement (AWS_ECS_TASK_PATCHING_RETIREMENT)│
│  Rule 2: aws.ec2   → Instance state terminated/shutting-down                │
│  Rule 3: aws.eks   → EKS Fargate Pod Scheduled Termination                 │
│  Rule 4: aws.health → EC2 scheduled maintenance                            │
│                                                                             │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AWS LAMBDA (Formatter)                                    │
│                                                                             │
│  • Routes events by source (aws.health / aws.ec2 / aws.eks)                │
│  • Enriches EC2 events with instance tags via ec2:DescribeTags              │
│  • Identifies Karpenter nodes (karpenter.sh/nodepool tag)                   │
│  • Identifies EKS Auto Mode nodes (aws:eks:cluster-name tag)               │
│  • Filters out non-K8s EC2 terminations (noise reduction)                   │
│  • Formats Slack Block Kit messages with full context                       │
│                                                                             │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SLACK (Incoming Webhook)                                  │
│                                                                             │
│  ⚠️  ECS Fargate Task Retirement Scheduled                                  │
│  🔄 Node Terminated — Karpenter (NodePool: default)                         │
│  🤖 Node Terminated — EKS Auto Mode                                        │
│  🔧 EC2 Scheduled Maintenance                                              │
│  ☸️  EKS Fargate Pod Scheduled Termination                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

The pipeline flow:

1. AWS services emit events to EventBridge (Health events, EC2 state changes, EKS events)
2. EventBridge rules match specific event patterns and invoke the Lambda function
3. The Lambda function determines the event type, enriches it with context (EC2 tags for Karpenter/Auto Mode identification), and formats a Slack Block Kit message
4. The formatted message is posted to your Slack channel via Incoming Webhook

For EC2 instance terminations specifically, the Lambda calls `ec2:DescribeTags` to check if the terminated instance was a Karpenter-managed node or an EKS Auto Mode node. If it has no Kubernetes-related tags, the event is silently dropped to avoid flooding your channel with unrelated EC2 terminations.

## How It's Built

### Tech Stack

| Component | Technology | Purpose |
|---|---|---|
| Infrastructure as Code | Terraform (modular) | Provisions all AWS resources |
| Event Routing | Amazon EventBridge | Pattern-matches events and routes to Lambda |
| Alert Formatting | AWS Lambda (Python 3.12) | Enriches events with tags, formats Slack messages |
| Notification Delivery | Slack Incoming Webhook | Delivers formatted alerts to a channel |
| Messaging Bus | Amazon SNS | Optional fan-out for multi-channel delivery |
| In-Cluster Monitoring | Kubernetes Event Exporter | Captures Karpenter disruption reasons (optional) |

### Project Structure

```
.
├── README.md
├── Makefile                              # Quick commands for deploy, test, lint
├── .gitignore
├── scripts/
│   └── deploy.sh                         # Interactive deployment script
├── terraform/
│   ├── main.tf                           # Root module — wires all child modules together
│   ├── variables.tf                      # Root-level inputs
│   ├── outputs.tf                        # Root-level outputs
│   ├── modules/
│   │   ├── eventbridge-rules/            # All 4 EventBridge rules + targets + permissions
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── lambda-formatter/             # Lambda function + IAM role + CloudWatch logs
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── src/
│   │   │       └── handler.py            # Event formatter (all event types)
│   │   ├── sns-topic/                    # SNS topic for optional fan-out
│   │   │   ├── main.tf
│   │   │   └── variables.tf
│   │   └── slack-integration/            # AWS Chatbot setup (optional)
│   │       ├── main.tf
│   │       └── variables.tf
│   └── environments/
│       ├── dev.tfvars
│       └── prod.tfvars
├── kubernetes/
│   └── event-exporter/                   # In-cluster Karpenter event monitoring
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── rbac.yaml
│       ├── configmap.yaml
│       ├── deployment.yaml
│       └── secret.yaml
└── tests/
    ├── test_handler_local.py             # Local test (no AWS credentials needed)
    └── events/                           # Sample EventBridge events for testing
        ├── ecs_task_retirement.json
        ├── ec2_instance_terminated.json
        ├── eks_fargate_pod_termination.json
        └── ec2_scheduled_maintenance.json
```

### Terraform Modules

The infrastructure is split into four focused modules:

- **`eventbridge-rules`** — Creates the four EventBridge rules that match lifecycle events, targets them to the Lambda function, and grants invoke permissions. Each rule can be independently enabled/disabled via variables.
- **`lambda-formatter`** — Packages and deploys the Python Lambda function, creates its IAM role with `ec2:DescribeTags` and CloudWatch Logs permissions, and configures the Slack webhook URL as an environment variable.
- **`sns-topic`** — Creates an SNS topic for optional fan-out (useful if you want to add email, PagerDuty, or other subscribers alongside Slack).
- **`slack-integration`** — Optionally provisions AWS Chatbot via CloudFormation for native Slack integration (requires one-time OAuth setup in the AWS Console).

## Deployment Guide

### Prerequisites

Before you begin, ensure you have:

- **AWS CLI** installed and configured with credentials that have permissions to create EventBridge rules, Lambda functions, IAM roles, SNS topics, and CloudWatch log groups
- **Terraform >= 1.5** installed ([install guide](https://developer.hashicorp.com/terraform/install))
- **A Slack Incoming Webhook URL** — create one at https://api.slack.com/messaging/webhooks
- **Python 3.11+** (for running local tests)
- **(Optional)** `kubectl` configured with cluster access (for the Kubernetes Event Exporter)

### Step 1: Clone the Repository

```bash
git clone <your-repo-url>
cd "Notification Pipeline"
```

### Step 2: Create a Slack Incoming Webhook

1. Go to https://api.slack.com/apps and create a new app (or use an existing one)
2. Navigate to **Incoming Webhooks** and activate them
3. Click **Add New Webhook to Workspace**
4. Select the channel where you want alerts delivered (e.g., `#infra-alerts`)
5. Copy the webhook URL — you'll need it in the next step

### Step 3: Set Environment Variables

```bash
# Required — your Slack webhook URL
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

# Optional — override the target environment (defaults to dev)
export ENV="dev"
```

### Step 4: Initialize Terraform

```bash
cd terraform
terraform init
```

This downloads the AWS and Archive providers and initializes all four modules.

### Step 5: Review the Plan

```bash
# For dev environment
terraform plan \
  -var-file=environments/dev.tfvars \
  -var="slack_webhook_url=${SLACK_WEBHOOK_URL}"

# For production
terraform plan \
  -var-file=environments/prod.tfvars \
  -var="slack_webhook_url=${SLACK_WEBHOOK_URL}"
```

Review the output to confirm the resources that will be created:
- 1 SNS topic
- 1 Lambda function + IAM role + 2 IAM policies + CloudWatch log group
- 4 EventBridge rules + 4 targets + 4 Lambda permissions

### Step 6: Apply the Infrastructure

```bash
terraform apply \
  -var-file=environments/dev.tfvars \
  -var="slack_webhook_url=${SLACK_WEBHOOK_URL}"
```

Type `yes` when prompted to confirm.

### Step 7: Verify the Deployment

```bash
# Check the Lambda function was created
aws lambda get-function --function-name infra-lifecycle-alerts-dev-formatter

# Check EventBridge rules exist
aws events list-rules --name-prefix infra-lifecycle-alerts-dev

# Check the Lambda can be invoked
aws lambda invoke \
  --function-name infra-lifecycle-alerts-dev-formatter \
  --payload '{"source":"aws.eks","detail-type":"EKS Fargate Pod Scheduled Termination","detail":{"clusterName":"test","fargateProfileName":"default","podName":"test-pod","namespace":"default"},"region":"us-east-1","account":"123456789012","time":"2026-01-01T00:00:00Z"}' \
  /tmp/lambda-response.json && cat /tmp/lambda-response.json
```

### Step 8: Send Test Events

```bash
# Go back to the project root
cd ..

# Send all test events to EventBridge
aws events put-events --entries file://tests/events/ecs_task_retirement.json
aws events put-events --entries file://tests/events/ec2_instance_terminated.json
aws events put-events --entries file://tests/events/eks_fargate_pod_termination.json
aws events put-events --entries file://tests/events/ec2_scheduled_maintenance.json
```

Check your Slack channel — you should see formatted alerts for the ECS retirement, EKS pod termination, and EC2 maintenance events. The EC2 instance terminated event will only produce an alert if the instance has Karpenter or EKS tags.

### Step 9: Configure ECS Task Retirement Wait Period (Recommended)

```bash
# Set to 14 days for maximum lead time before AWS retires your tasks
aws ecs put-account-setting-default \
  --name fargateTaskRetirementWaitPeriod \
  --value 14
```

This gives you 14 days between receiving the notification and AWS actually stopping your tasks.

### Step 10: Deploy Kubernetes Event Exporter (Optional)

This step adds in-cluster monitoring for Karpenter disruption events. It tells you WHY a node was terminated (expireAfter, drift, consolidation, etc.) — context that the EC2 state change event alone doesn't provide.

```bash
# Update the Slack webhook URL in the secret
# Edit kubernetes/event-exporter/secret.yaml and replace the placeholder URL

# Deploy to your cluster
kubectl apply -k kubernetes/event-exporter/

# Verify it's running
kubectl get pods -n monitoring -l app.kubernetes.io/name=event-exporter

# Check logs
kubectl logs -n monitoring -l app.kubernetes.io/name=event-exporter
```

### Using the Makefile (Alternative)

If you prefer shorter commands, the Makefile wraps all of the above:

```bash
# Set your webhook URL
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Initialize Terraform
make init

# Plan (defaults to dev, use ENV=prod for production)
make plan

# Apply
make apply

# Apply to production
make apply ENV=prod

# Run local tests (no AWS needed)
make test-local

# Send test events to EventBridge (requires AWS credentials)
make test-events

# Deploy Kubernetes Event Exporter
make deploy-k8s

# Tear down
make destroy
```

### Using the Deploy Script (Alternative)

For a guided interactive deployment:

```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
./scripts/deploy.sh dev    # or prod
```

The script validates prerequisites, verifies AWS credentials, runs plan, asks for confirmation, then applies.

---

## Event Coverage

### What Gets Captured

| Event Type | Source | EventBridge Pattern | Alert Content |
|---|---|---|---|
| ECS Fargate Task Retirement | `aws.health` | `AWS_ECS_TASK_PATCHING_RETIREMENT` | Affected tasks/services, retirement date, account, region |
| EC2 Scheduled Maintenance | `aws.health` | EC2 `scheduledChange` | Instance IDs, maintenance type, timing |
| Karpenter Node Termination | `aws.ec2` | Instance state → `terminated` | NodePool, NodeClaim, capacity type, instance type, cluster |
| EKS Auto Mode Node Termination | `aws.ec2` | Instance state → `terminated` | Node group, cluster, instance type |
| EKS Fargate Pod Termination | `aws.eks` | `EKS Fargate Pod Scheduled Termination` | Cluster, Fargate profile, pod name, namespace |

### How Karpenter Nodes Are Identified

When an EC2 instance is terminated, the Lambda checks its tags to determine if it's a managed Kubernetes node:

| Tag Key | Indicates |
|---|---|
| `karpenter.sh/nodepool` | Karpenter-managed node — includes NodePool name |
| `karpenter.sh/nodeclaim` | Specific NodeClaim that provisioned this instance |
| `karpenter.sh/capacity-type` | `spot` or `on-demand` |
| `aws:eks:cluster-name` | EKS cluster this node belongs to |
| `eks:nodegroup-name` | EKS managed node group (if applicable) |
| `kubernetes.io/cluster/<name>` | Alternative cluster identification tag |
| `node.kubernetes.io/instance-type` | EC2 instance type (e.g., m5.xlarge) |

If none of these tags are present, the termination event is silently dropped — this prevents noise from unrelated EC2 instances being terminated in the same account.

### What Triggers Karpenter Node Termination

| Trigger | Type | Pre-spins Replacement? | Respects Disruption Budgets? |
|---|---|---|---|
| `expireAfter` TTL (default 720h / 30 days) | Forceful | No | No |
| Drift (AMI update, config change) | Graceful | Yes | Yes |
| Consolidation (underutilized) | Graceful | Yes | Yes |
| Emptiness (no pods) | Graceful | N/A | Yes |
| Spot Interruption (2-min warning) | Forceful | Yes (parallel) | No |
| Instance Health Failure | Forceful | No | No |
| Manual `kubectl delete node` | Manual | No | No |

---

## In-Cluster Monitoring (Kubernetes Event Exporter)

The EventBridge-based pipeline tells you THAT a node was terminated. The Kubernetes Event Exporter tells you WHY — it watches for Karpenter's native Kubernetes events:

| Event Reason | Meaning |
|---|---|
| `DisruptionInitiated` | Karpenter selected this node for disruption |
| `DisruptionTerminating` | Node is actively being drained and terminated |
| `Unconsolidatable` | Node cannot be consolidated (informational) |
| `SpotInterrupted` | Spot instance reclaimed by AWS |
| `InstanceUnhealthy` | Instance failed health checks |

The Event Exporter deployment in `kubernetes/event-exporter/` is configured to:
- Watch for Karpenter disruption events and NodeClaim lifecycle events
- Format them as Slack Block Kit messages
- Post directly to your Slack webhook
- Filter out noisy events (pod scheduling, image pulls, etc.)

---

## Testing

### Local Testing (No AWS Credentials Needed)

```bash
python3 tests/test_handler_local.py
```

This runs all four event types through the Lambda handler with mocked boto3 calls and prints the formatted Slack messages to stdout. Useful for validating formatting changes.

### Integration Testing (Requires AWS Credentials)

```bash
# Send sample events to EventBridge — they'll flow through the full pipeline
make test-events

# Or individually:
aws events put-events --entries file://tests/events/ecs_task_retirement.json
aws events put-events --entries file://tests/events/ec2_instance_terminated.json
aws events put-events --entries file://tests/events/eks_fargate_pod_termination.json
aws events put-events --entries file://tests/events/ec2_scheduled_maintenance.json
```

### Verifying Karpenter Events In-Cluster

```bash
# Watch for Karpenter disruption events
kubectl get events --field-selector reason=DisruptionInitiated -A
kubectl get events --field-selector reason=DisruptionTerminating -A

# Check NodeClaim status
kubectl get nodeclaims -o wide
```

---

## Configuration

### Terraform Variables

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region to deploy resources | `us-east-1` |
| `project_name` | Prefix for all resource names | `infra-lifecycle-alerts` |
| `slack_webhook_url` | Slack Incoming Webhook URL (sensitive) | — (required) |
| `slack_channel` | Slack channel name for Lambda posts | `infra-alerts` |
| `slack_workspace_id` | Slack workspace ID for AWS Chatbot (optional) | `""` |
| `slack_channel_id` | Slack channel ID for AWS Chatbot (optional) | `""` |
| `enable_ecs_retirement_alerts` | Enable ECS Fargate task retirement rule | `true` |
| `enable_ec2_termination_alerts` | Enable EC2 instance termination rule | `true` |
| `enable_eks_events` | Enable EKS service events rule | `true` |
| `enable_ec2_health_alerts` | Enable EC2 scheduled maintenance rule | `true` |
| `lambda_log_retention_days` | CloudWatch log retention | `14` |
| `tags` | Tags applied to all resources | `Project`, `ManagedBy` |

### Environment Files

- `terraform/environments/dev.tfvars` — Development settings (7-day log retention, `-dev` suffix)
- `terraform/environments/prod.tfvars` — Production settings (30-day log retention)

---

## Cost

| Component | Cost |
|---|---|
| EventBridge Rules | Free (custom events: $1 per million) |
| SNS Topic | Free tier: 1M publishes/month |
| Lambda Function | Free tier: 1M requests/month, 400K GB-seconds |
| CloudWatch Logs | $0.50/GB ingested (minimal for this use case) |
| AWS Chatbot | Free |
| Kubernetes Event Exporter | Runs as a pod (~10m CPU, 64Mi memory) |

For most environments, this entire pipeline runs well within the AWS free tier.

---

## Teardown

```bash
# Destroy all AWS resources
cd terraform
terraform destroy \
  -var-file=environments/dev.tfvars \
  -var="slack_webhook_url=${SLACK_WEBHOOK_URL}"

# Remove Kubernetes Event Exporter (if deployed)
kubectl delete -k kubernetes/event-exporter/
```

Or via Makefile:

```bash
make destroy
make undeploy-k8s
```

---

## References

- [AWS Fargate Task Retirement Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-maintenance.html)
- [Improving Operational Visibility with Fargate Task Retirement Notifications (AWS Blog)](https://aws.amazon.com/blogs/containers/improving-operational-visibility-with-aws-fargate-task-retirement-notifications/)
- [Karpenter Disruption Concepts](https://karpenter.sh/docs/concepts/disruption/)
- [Karpenter NodePools — expireAfter](https://karpenter.sh/docs/concepts/nodepools/)
- [Amazon EKS Events in EventBridge](https://docs.aws.amazon.com/eventbridge/latest/ref/events-ref-eks.html)
- [EC2 Instance State-change Events](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instance-state-changes.html)
- [EKS Node Monitoring Agent](https://docs.aws.amazon.com/eks/latest/userguide/node-health-nma.html)
- [Kubernetes Event Exporter](https://github.com/resmoio/kubernetes-event-exporter)
- [AWS Health Aware (Reference Architecture)](https://github.com/aws-samples/aws-health-aware)
- [Capturing Fargate Task Retirement Notifications (Sample Code)](https://github.com/aws-samples/capturing-aws-fargate-task-retirement-notifications)

---

## License

MIT
