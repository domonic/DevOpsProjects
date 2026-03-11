# Troubleshooting EKS Node Taint Not Removed: node.cloudprovider.kubernetes.io/uninitialized

## Issue Description

EKS nodes remain tainted with **`node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule`** after joining the cluster, preventing pod scheduling. The **kubelet** will apply this taint **prior** to joining the cluster, and **cloud-controller-manager** will remove it **after** it fulfills its duties.

&nbsp;

## Root Cause

The cloud-controller-manager lacks the **`ec2:DescribeAvailabilityZones`** permission required to initialize nodes. This can occur in two scenarios:

1. **Missing from attached managed policy**: The permission is not included in any identity-based policies attached to the cluster role
2. **Blocked by permission boundary**: The permission exists in the attached managed policy but is not included in the permission boundary policy, which acts as a maximum allowed permissions filter and blocks it

In both cases, the effective result is the same: the cloud-controller-manager cannot describe availability zones and therefore cannot remove the initialization taint.

&nbsp;

## Symptoms

- Nodes show as Ready but have the uninitialized taint
- Pods remain in Pending state with **`Warning  FailedScheduling default-scheduler  0/1 nodes are available: 1 node(s) had untolerated taint {node.cloudprovider.kubernetes.io/uninitialized: true}. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling`**
- Cloud Trail logs show permission denied errors

&nbsp;

## Troubleshooting Steps

### 1. Verify the Taint on the Node

```bash
kubectl describe node <NODE_NAME> | grep -A5 Taints
```

Expected output showing the problematic taint:
```
Taints: node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule
```
&nbsp;
### 2. Query Control Plane Logs for Node Operations

Check if the cloud-controller-manager attempted to remove the taint:

```bash
fields @timestamp, user.username, verb, @message
| filter @logStream like /audit/
| filter requestURI like /\/api\/v1\/nodes/
| filter objectRef.name = "NODE_NAME"
| filter user.username like /cloud-controller-manager/ or userAgent like /cloud-controller-manager/
| sort @timestamp desc
```

If no results appear, the cloud-controller-manager is not successfully updating the node.

&nbsp;

### 3. Check Node Update History

Query all create/update/patch operations on the node:

```bash
fields @timestamp, user.username, verb, responseObject.spec.taints
| filter @logStream like /audit/
| filter requestURI like /\/api\/v1\/nodes/
| filter objectRef.name = "NODE_NAME"
| filter verb in ["create", "update", "patch"]
| sort @timestamp asc
```

This shows the progression of taints over time. If the taint persists across all operations, it was never successfully removed.

&nbsp;

### 4. Search CloudTrail for Access Denied Events

Query CloudTrail for permission errors from the EKS cluster role:

```bash
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue=<CLUSTER_ROLE_NAME> \
    --max-results 50 \
    --query 'Events[?contains(CloudTrailEvent, `AccessDenied`) || contains(CloudTrailEvent, `ec2:DescribeAvailabilityZones`)].CloudTrailEvent' \
    --output text | jq
```

Alternatively, use the CloudTrail console to search for:
- Access denied events filtered by the cluster role name
- Access denied events for the `ec2:DescribeAvailabilityZones` API call

&nbsp;

```bash
{
    "eventVersion": "1.11",
        "invokedBy": "eks.amazonaws.com"
        ...
    }
    ...
    "eventTime": "2026-02-26T13:55:26Z",
    "eventSource": "ec2.amazonaws.com",
    "eventName": "DescribeAvailabilityZones",
    "awsRegion": "eu-west-1",
    "sourceIPAddress": "eks.amazonaws.com",
    "userAgent": "eks.amazonaws.com",
    "errorCode": "Client.UnauthorizedOperation",
    "errorMessage": "You are not authorized to perform this operation. User: arn:aws:sts::REDACTED:assumed-role/REDACTED is not authorized to perform: ec2:DescribeAvailabilityZones because no permissions boundary allows the ec2:DescribeAvailabilityZones action",
    "requestParameters": {
        "availabilityZoneSet": {},
        "availabilityZoneIdSet": {}
    },
    "responseElements": null,
    "readOnly": true,
    "eventType": "AwsApiCall",
    "managementEvent": true,
    "eventCategory": "Management"
}
```


&nbsp;

### 5. Review IAM Role Configuration

#### Check the EKS Cluster IAM Role

⚠️ **Note:** All of the following information can also be retrieved via the IAM console by navigating to the cluster role.

```bash
aws iam get-role --role-name <CLUSTER_ROLE_NAME>
```

⚠️ **Note:** the `PermissionsBoundary` field in the output.

#### List Attached Managed Policies

```bash
aws iam list-attached-role-policies --role-name <CLUSTER_ROLE_NAME>
```

#### Get Permission Boundary Policy

```bash
aws iam get-policy --policy-arn <PERMISSION_BOUNDARY_ARN>
aws iam get-policy-version --policy-arn <PERMISSION_BOUNDARY_ARN> --version-id <VERSION_ID>
```

⚠️ **Note:** Example Permission Boundary

&nbsp;

```bash
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Sid": "AmazonEKSWorkerNodePolicyforEC2"
    },
    {
      "Action": [
        "eks:DescribeCluster"
      ],
      "Resource": [
        "arn:aws:eks:*:<ACCOUNT_ID>:cluster/<CLUSTER_NAME_PATTERN",
        "arn:aws:eks:*:<ACCOUNT_ID>:cluster/<CLUSTER_NAME_PATTERN",
        "arn:aws:eks:*:<ACCOUNT_ID>:cluster/<CLUSTER_NAME_PATTERN",
        "arn:aws:eks:*:<ACCOUNT_ID>:cluster/<CLUSTER_NAME_PATTERN"
      ],
      "Effect": "Allow",
      "Sid": "AmazonEKSWorkerNodePolicyforCluster"
    },
    {
      "Action": [
        "tag:getResources",
        "tag:getTagKeys",
        "tag:getTagValues",
        "resource-groups:Get*",
        "resource-groups:List*",
        "resource-groups:Search*",
        "cloudformation:DescribeStacks",
        "cloudformation:ListStackResources"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Sid": "ResourceGroupsandTagEditorReadOnlyAccess"
    },
    {
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:GetLifecyclePolicy",
        "ecr:GetLifecyclePolicyPreview",
        "ecr:ListTagsForResource",
        "ecr:DescribeImageScanFindings"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Sid": "AmazonEC2ContainerRegistryReadOnly"
    },
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Sid": "NodeAutoScalingReadOnly"
    },
    {
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": [
        "arn:aws:autoscaling:*:<ACCOUNT_ID>:autoScalingGroup:*:autoScalingGroupName/*<ASG_NAME_PATTERN>*"
      ],
      "Effect": "Allow"
    }
  ]
}
```

&nbsp;


#### Get Attached Managed Policy

```bash
aws iam get-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam get-policy-version --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --version-id <VERSION_ID>
```

⚠️ **Note:** Example Attached Cluster Policy

&nbsp;


```bash
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Sid" : "AmazonEKSClusterPolicy",
      "Effect" : "Allow",
      "Action" : [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateRoute",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteRoute",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteVolume",
        "ec2:DescribeInstances",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:DescribeVpcs",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeAvailabilityZones",
        "ec2:DetachVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyVolume",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeInstanceTopology",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
        "elasticloadbalancing:AttachLoadBalancerToSubnets",
        "elasticloadbalancing:ConfigureHealthCheck",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateLoadBalancerListeners",
        "elasticloadbalancing:CreateLoadBalancerPolicy",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancerListeners",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DescribeLoadBalancerPolicies",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DetachLoadBalancerFromSubnets",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
        "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
        "kms:DescribeKey"
      ],
      "Resource" : "*"
    },
    {
      "Sid" : "AmazonEKSClusterPolicySLRCreate",
      "Effect" : "Allow",
      "Action" : "iam:CreateServiceLinkedRole",
      "Resource" : "*",
      "Condition" : {
        "StringEquals" : {
          "iam:AWSServiceName" : "elasticloadbalancing.amazonaws.com"
        }
      }
    },
    {
      "Sid" : "AmazonEKSClusterPolicyENIDelete",
      "Effect" : "Allow",
      "Action" : "ec2:DeleteNetworkInterface",
      "Resource" : "*",
      "Condition" : {
        "StringEquals" : {
          "ec2:ResourceTag/eks:eni:owner" : "amazon-vpc-cni"
        }
      }
    }
  ]
}
```

&nbsp;


### 6. Simulate IAM Policy to Confirm Denial

Test if the role can perform the required action:

```bash
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::<ACCOUNT_ID>:role/<CLUSTER_ROLE_NAME> \
    --action-names ec2:DescribeAvailabilityZones \
    --resource-arns "*"
```

Expected output showing implicit deny:

```json
{
  "EvaluationResults": [
    {
      "EvalActionName": "ec2:DescribeAvailabilityZones",
      "EvalDecision": "implicitDeny",
      "EvalResourceName": "*",
      "MatchedStatements": [],
      "OrganizationsDecisionDetail": {
        "AllowedByOrganizations": "false"
      }
    }
  ]
}
```

&nbsp;

### 7. Compare Permission Boundary vs Managed Policy

**Permission Boundary (Missing ec2:DescribeAvailabilityZones):**
```json
{
    "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:DescribeVpcs"
         ...
    ],
    "Resource": "*",
    "Effect": "Allow"
}
```

**AmazonEKSClusterPolicy (Includes ec2:DescribeAvailabilityZones):**
```json
{
    "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeAvailabilityZones",
        ...
    ],
    "Resource": "*",
    "Effect": "Allow"
}
```

&nbsp;

## Resolution

Add **`ec2:DescribeAvailabilityZones`** to the **Permission Boundary policy**:

```json
{
    "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:DescribeVpcs",
        "ec2:DescribeAvailabilityZones"
    ],
    "Resource": "*",
    "Effect": "Allow",
    "Sid": "AmazonEKSWorkerNodePolicyforEC2"
}
```

### Update the Permission Boundary Policy

1. Create a new policy version:
```bash
aws iam create-policy-version \
    --policy-arn <PERMISSION_BOUNDARY_ARN> \
    --policy-document file://updated-policy.json \
    --set-as-default
```

2. Verify the update:
```bash
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::<ACCOUNT_ID>:role/<CLUSTER_ROLE_NAME> \
    --action-names ec2:DescribeAvailabilityZones \
    --resource-arns "*"
```

Expected output after fix:
```json
{
  "EvaluationResults": [
    {
      "EvalActionName": "ec2:DescribeAvailabilityZones",
      "EvalDecision": "allowed",
      "EvalResourceName": "*"
    }
  ]
}
```

### Verify Taint Removal

The cloud-controller-manager should automatically remove the taint within a few minutes. Monitor the node:

```bash
kubectl describe node <NODE_NAME> | grep -A5 Taints
```

Expected output after successful removal:
```
Taints: <none>
```

&nbsp;

## Key Concepts

**Permission Boundaries**: Act as a guardrail that defines the maximum permissions an IAM entity can have. Even if an identity-based policy grants a permission, the permission boundary can block it.

**Effective Permissions**: The intersection of:
- Identity-based policies (managed/inline policies attached to the role)
- Permission boundaries
- Resource-based policies
- SCPs (if using AWS Organizations)

&nbsp;

## Prevention

- Ensure permission boundaries include all permissions required by AWS managed policies
- Test IAM changes using `simulate-principal-policy` before applying to production
- Monitor CloudTrail for AccessDenied events on critical roles
- Document custom permission boundaries and their intended restrictions

&nbsp;

## Related AWS Documentation

- [EKS IAM Roles](https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html)
- [EKS Cluster Policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEKSClusterPolicy.html#AmazonEKSClusterPolicy-json)
-  [IAM Permission Boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
- [Testing IAM Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html)
- [Github Issue](https://github.com/awslabs/amazon-eks-ami/issues/1446#issuecomment-1741399761)