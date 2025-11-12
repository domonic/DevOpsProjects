#!/bin/bash

set -e

# Configuration
KARPENTER_VERSION="${KARPENTER_VERSION:-v0.37.7}"
CLUSTER_NAME="${CLUSTER_NAME}"
KARPENTER_NAMESPACE="${KARPENTER_NAMESPACE:-karpenter}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    if [ -z "$CLUSTER_NAME" ]; then
        error "CLUSTER_NAME environment variable is required"
    fi
    
    command -v kubectl >/dev/null 2>&1 || error "kubectl is required but not installed"
    command -v helm >/dev/null 2>&1 || error "helm is required but not installed"
    
    kubectl cluster-info >/dev/null 2>&1 || error "kubectl cannot connect to cluster"
    
    log "Prerequisites validated"
}

# Label and annotate CRDs for Helm management
label_crds() {
    log "Labeling and annotating Karpenter CRDs..."
    
    local crds=(
        "ec2nodeclasses.karpenter.k8s.aws"
        "nodepools.karpenter.sh"
        "nodeclaims.karpenter.sh"
        "machines.karpenter.sh"
        "provisioners.karpenter.sh"
        "awsnodetemplates.karpenter.k8s.aws"
    )
    
    for crd in "${crds[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            kubectl label crd "$crd" app.kubernetes.io/managed-by=Helm --overwrite
            kubectl annotate crd "$crd" meta.helm.sh/release-name=karpenter-crd --overwrite
            kubectl annotate crd "$crd" meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" --overwrite
            log "Labeled CRD: $crd"
        else
            warn "CRD not found: $crd"
        fi
    done
}

# Label and annotate RBAC resources
label_rbac() {
    log "Labeling and annotating Karpenter RBAC resources..."
    
    # ClusterRoleBindings
    local cluster_role_bindings=("karpenter-core" "karpenter" "karpenter-admin")
    for crb in "${cluster_role_bindings[@]}"; do
        if kubectl get clusterrolebinding "$crb" >/dev/null 2>&1; then
            kubectl annotate clusterrolebinding "$crb" meta.helm.sh/release-name=karpenter --overwrite
            kubectl annotate clusterrolebinding "$crb" meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" --overwrite
            log "Annotated ClusterRoleBinding: $crb"
        fi
    done
    
    # DNS Role and RoleBinding in kube-system
    if kubectl get role karpenter-dns -n kube-system >/dev/null 2>&1; then
        kubectl annotate role karpenter-dns meta.helm.sh/release-name=karpenter -n kube-system --overwrite
        kubectl annotate role karpenter-dns meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" -n kube-system --overwrite
        kubectl annotate rolebinding karpenter-dns meta.helm.sh/release-name=karpenter -n kube-system --overwrite
        kubectl annotate rolebinding karpenter-dns meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" -n kube-system --overwrite
        log "Annotated DNS RBAC resources"
    fi
    
    # Lease Role and RoleBinding in kube-node-lease
    if kubectl get role karpenter-lease -n kube-node-lease >/dev/null 2>&1; then
        kubectl annotate role karpenter-lease meta.helm.sh/release-name=karpenter -n kube-node-lease --overwrite
        kubectl annotate role karpenter-lease meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" -n kube-node-lease --overwrite
        kubectl annotate rolebinding karpenter-lease meta.helm.sh/release-name=karpenter -n kube-node-lease --overwrite
        kubectl annotate rolebinding karpenter-lease meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" -n kube-node-lease --overwrite
        log "Annotated Lease RBAC resources"
    fi

    # Karpenter Role and RoleBinding in kube-node-lease
    if kubectl get role karpenter -n kube-node-lease >/dev/null 2>&1; then
        kubectl annotate role karpenter meta.helm.sh/release-name=karpenter -n kube-node-lease --overwrite
        kubectl annotate role karpenter meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" -n kube-node-lease --overwrite
        kubectl annotate rolebinding karpenter meta.helm.sh/release-name=karpenter -n kube-node-lease --overwrite
        kubectl annotate rolebinding karpenter meta.helm.sh/release-namespace="$KARPENTER_NAMESPACE" -n kube-node-lease --overwrite
        log "Annotated Lease RBAC resources"
    fi
}

# Check and resolve Helm lock
resolve_helm_lock() {
    log "Checking for Helm operation locks..."
    
    # Check if there's a pending release
    if helm list -n "$KARPENTER_NAMESPACE" | grep -q "pending"; then
        warn "Found pending Helm release. Attempting to rollback..."
        helm rollback karpenter -n "$KARPENTER_NAMESPACE" || true
        sleep 10
    fi
    
    # Get Helm secrets that might be causing locks
    local secrets=$(kubectl get secrets -n "$KARPENTER_NAMESPACE" -l owner=helm,name=karpenter --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    if [ -n "$secrets" ]; then
        log "Found Helm secrets: $secrets"
        
        # Check for pending-install or pending-upgrade secrets
        for secret in $secrets; do
            local status=$(kubectl get secret "$secret" -n "$KARPENTER_NAMESPACE" -o jsonpath='{.metadata.labels.status}' 2>/dev/null || echo "")
            if [[ "$status" == "pending-install" || "$status" == "pending-upgrade" ]]; then
                warn "Removing stuck Helm secret: $secret (status: $status)"
                kubectl delete secret "$secret" -n "$KARPENTER_NAMESPACE"
            fi
        done
    fi
    
    # Wait a moment for cleanup
    sleep 5
}

# Force cleanup if needed
force_cleanup() {
    log "Performing force cleanup..."
    
    # Delete any stuck pods
    kubectl delete pods -n "$KARPENTER_NAMESPACE" --field-selector=status.phase=Pending --force --grace-period=0 2>/dev/null || true
    
    # Check deployment status
    if kubectl get deployment karpenter -n "$KARPENTER_NAMESPACE" >/dev/null 2>&1; then
        local ready=$(kubectl get deployment karpenter -n "$KARPENTER_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(kubectl get deployment karpenter -n "$KARPENTER_NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready" != "$desired" ]; then
            warn "Karpenter deployment not ready ($ready/$desired). Restarting..."
            kubectl rollout restart deployment/karpenter -n "$KARPENTER_NAMESPACE"
            kubectl rollout status deployment/karpenter -n "$KARPENTER_NAMESPACE" --timeout=300s
        fi
    fi
}

# Upgrade Karpenter CRDs
upgrade_crds() {
    log "Upgrading Karpenter CRDs to version $KARPENTER_VERSION..."
    
    helm upgrade --install karpenter-crd \
        oci://public.ecr.aws/karpenter/karpenter-crd \
        --version "$KARPENTER_VERSION" \
        --namespace "$KARPENTER_NAMESPACE" \
        --create-namespace \
        --wait
    
    log "Karpenter CRDs upgraded successfully"
}

# Upgrade Karpenter controller with retry logic
upgrade_controller() {
    log "Upgrading Karpenter controller to version $KARPENTER_VERSION..."
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Upgrade attempt $attempt/$max_attempts..."
        
        if helm upgrade --install karpenter \
            oci://public.ecr.aws/karpenter/karpenter \
            --version "$KARPENTER_VERSION" \
            --namespace "$KARPENTER_NAMESPACE" \
            --create-namespace \
            --set "settings.clusterName=$CLUSTER_NAME" \
            --set controller.resources.requests.cpu=1 \
            --set controller.resources.requests.memory=1Gi \
            --set controller.resources.limits.cpu=1 \
            --set controller.resources.limits.memory=1Gi \
            --timeout=10m \
            --force; then
            log "Karpenter controller upgraded successfully!"
            return 0
        else
            warn "Upgrade attempt $attempt failed"
            if [ $attempt -lt $max_attempts ]; then
                log "Cleaning up and retrying..."
                resolve_helm_lock
                force_cleanup
                sleep 10
            fi
            ((attempt++))
        fi
    done
    
    error "All upgrade attempts failed"
}

# Verify deployment
verify_deployment() {
    log "Verifying Karpenter deployment..."
    
    kubectl get deployment karpenter -n "$KARPENTER_NAMESPACE" -o wide
    kubectl get pods -n "$KARPENTER_NAMESPACE" -l app.kubernetes.io/name=karpenter
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/karpenter -n "$KARPENTER_NAMESPACE"
    
    log "Karpenter deployment verified"
}

# Main execution
main() {
    log "Starting Karpenter upgrade process..."
    log "Target version: $KARPENTER_VERSION"
    log "Cluster: $CLUSTER_NAME"
    log "Namespace: $KARPENTER_NAMESPACE"
    
    validate_prerequisites
    resolve_helm_lock
    force_cleanup
    label_crds
    label_rbac
    upgrade_crds
    upgrade_controller
    verify_deployment
    
    log "Karpenter upgrade completed successfully!"
    log "Current Karpenter version:"
    kubectl get deployment karpenter -n "$KARPENTER_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}'
    echo
}

# Help function
show_help() {
    cat << EOF
Karpenter Upgrade Script

Usage: $0 [OPTIONS]

Environment Variables:
  KARPENTER_VERSION    Target Karpenter version (default: v0.37.0)
  CLUSTER_NAME         EKS cluster name (required)
  KARPENTER_NAMESPACE  Karpenter namespace (default: karpenter)

Options:
  -h, --help          Show this help message

Examples:
  export CLUSTER_NAME=my-eks-cluster
  export KARPENTER_VERSION=v0.37.0
  $0

  CLUSTER_NAME=my-cluster KARPENTER_VERSION=v1.0.0 $0
EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
