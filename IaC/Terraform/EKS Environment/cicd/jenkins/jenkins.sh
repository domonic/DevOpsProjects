#!/bin/bash

set -e

# ========= USER CONFIGURATION ==========
CLUSTER_NAME="k8s-dev-eks"
REGION="us-west-2"
JENKINS_NAMESPACE="jenkins"
# =======================================

# 0. Dependencies check
for cmd in aws eksctl helm kubectl; do
  command -v $cmd >/dev/null || { echo "$cmd is required but not installed. Exiting."; exit 1; }
done

aws sts get-caller-identity >/dev/null || { echo "AWS CLI not configured. Exiting."; exit 1; }

eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$CLUSTER_NAME --approve

# 1. Update kubeconfig
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# 2. Install AWS Load Balancer Controller
POLICY_NAME="AWSLoadBalancerControllerIAMPolicyComplete"
SA_NAME="aws-load-balancer-controller"
SA_NAMESPACE="kube-system"

echo "Installing AWS Load Balancer Controller IAM policy..."
aws iam create-policy --policy-name $POLICY_NAME --policy-document file://iam-policy.json || echo "Policy exists."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "Creating IAM service account with eksctl..."
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --region=$REGION \
  --namespace=$SA_NAMESPACE \
  --name=$SA_NAME \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME \
  --approve \
  --override-existing-serviceaccounts

helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "Installing AWS Load Balancer Controller via Helm..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n $SA_NAMESPACE \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=$SA_NAME \
  --set region=$REGION \
  --set vpcId=$VPC_ID


# 3. Install Jenkins
kubectl create namespace $JENKINS_NAMESPACE || echo "Namespace exists."
helm repo add stable https://charts.helm.sh/stable
helm repo update

echo "Checking for default StorageClass..."
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [[ -z "$DEFAULT_SC" ]]; then
  echo "No default StorageClass found, setting 'gp2' as default (if exists)..."
  if kubectl get storageclass gp2 >/dev/null 2>&1; then
    kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    DEFAULT_SC="gp2"
    echo "'gp2' set as default StorageClass."
  else
    echo "Error: No default StorageClass and 'gp2' not found. Please create a StorageClass."
    exit 1
  fi
else
  echo "Default StorageClass is '$DEFAULT_SC'"
fi



cat <<EOF > jenkins-values.yaml
controller:
  ingress:
    ingressClassName: alb
    enabled: true
    annotations:
      alb.ingress.kubernetes.io/healthcheck-path: /jenkins/login
      alb.ingress.kubernetes.io/ingress-class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/group.name: jenkins-ingress
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/conditions.jenkins: |
        [
          {
            "Field": "path-pattern",
            "PathPatternConfig": {
              "Values": ["/jenkins", "/jenkins/*"]
            }
          }
        ]
    hosts: 
      - k8s-jenkinsingress-13a4fc1a1e-904436539.us-west-2.elb.amazonaws.com
    path: /jenkins
    pathType: Prefix
  serviceType: ClusterIP
  persistence:
    enabled: true
    storageClass: "$DEFAULT_SC"
    size: 10Gi
EOF

echo "Installing Jenkins..."
helm upgrade --install jenkins jenkins/jenkins \
  -n $JENKINS_NAMESPACE -f jenkins-values.yaml


echo "Waiting for Jenkins StatefulSet to be ready..."

kubectl -n jenkins patch sts jenkins --type merge -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "jenkins",
            "env": [
              {
                "name": "JENKINS_ROOT",
                "value": "/jenkins"
              }
            ]
          }
        ]
      }
    }
  }
}'


kubectl patch sts jenkins -n jenkins --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/image",
    "value": "docker.io/jenkins/jenkins:2.504.1-jdk21"
  }
]'


kubectl patch sts jenkins -n jenkins --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "JENKINS_OPTS",
      "value": "--prefix=/jenkins"
    }
  }
]'

kubectl rollout status statefulset jenkins -n jenkins --timeout=600s


# 5. Retrieve Admin Passwords
echo -e "\n🎉 Deployment complete!"
JENKINS_URL=$(kubectl get ingress -n jenkins jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "🚪 Jenkins URL:  $JENKINS_URL"
echo "🔑 Jenkins Admin Password:"
kubectl get secret -n $JENKINS_NAMESPACE jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode; echo

