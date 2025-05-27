#!/bin/bash

set -e

# ========= USER CONFIGURATION ==========
CLUSTER_NAME="k8s-dev-eks"
REGION="us-west-2"
ARGOCD_NAMESPACE="argocd"
# =======================================

#1. Install Argo CD
kubectl create namespace $ARGOCD_NAMESPACE || echo "Namespace exists."
kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


echo "Patching Argo CD server to use ClusterIP..."
kubectl patch svc argocd-server -n $ARGOCD_NAMESPACE -p '{"spec": {"type": "ClusterIP"}}'

echo "Creating Ingress for Argo CD..."
cat <<EOF | kubectl apply -n $ARGOCD_NAMESPACE -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  annotations:
    alb.ingress.kubernetes.io/ingress-class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: jenkins-ingress
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/success-codes: "200-399"
    alb.ingress.kubernetes.io/conditions.argocd: |
        [
          {
            "Field": "path-pattern",
            "PathPatternConfig": {
              "Values": ["/jenkins", "/jenkins/*"]
            }
          }
        ]
spec:
  ingressClassName: alb
  rules:
  - host: k8s-jenkinsingress-13a4fc1a1e-904436539.us-west-2.elb.amazonaws.com
    http:
      paths:
      - path: /argocd/*
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

echo "Patching Argo CD to allow HTTP access..."
#kubectl -n $ARGOCD_NAMESPACE patch deployment argocd-server --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--insecure","/usr/local/bin/argocd-server"]}]'

echo "Waiting for Argo CD to be ready..."
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.rootpath":"/argocd"}}'
kubectl rollout status deployment/argocd-server -n $ARGOCD_NAMESPACE

echo -e "\n🎉 Deployment complete!"

echo "🔑 Argo CD Admin Password:"
kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo