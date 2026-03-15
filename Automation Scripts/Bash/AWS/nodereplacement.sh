#!/bin/bash

# Controlled Node Replacement Script for Karpenter
# Run manually for testing

set -euo pipefail

# Configuration
NODEPOOL_LABEL="karpenter.sh/nodepool=default"
DRAIN_TIMEOUT="300s"
REPLACEMENT_WAIT="120"
LOG_FILE="/tmp/node-replacement.log"
MIN_NODE_AGE_HOURS="24"  # Only replace nodes older than 24 hours

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if it's Tuesday between 9-17 UTC (skip for manual testing)
check_maintenance_window() {
    # Commented out for manual testing
    # local day=$(date +%u)  # 1=Monday, 2=Tuesday
    # local hour=$(date +%H)
    # 
    # if [[ $day -ne 2 ]] || [[ $hour -lt 9 ]] || [[ $hour -ge 17 ]]; then
    #     log "Outside maintenance window (Tuesday 9-17 UTC). Exiting."
    #     exit 0
    # fi
    log "Manual execution - skipping maintenance window check"
}

# Get oldest node from the nodepool that's older than minimum age
get_oldest_node() {
    local min_age_seconds=$((MIN_NODE_AGE_HOURS * 3600))
    local current_time=$(date +%s)
    
    kubectl get nodes -l "$NODEPOOL_LABEL" \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.creationTimestamp}{"\n"}{end}' | \
    while read -r node_name creation_time; do
        if [[ -n "$node_name" && -n "$creation_time" ]]; then
            local node_age_seconds=$(( current_time - $(date -d "$creation_time" +%s) ))
            if [[ $node_age_seconds -gt $min_age_seconds ]]; then
                echo "$node_name"
                return 0
            fi
        fi
    done
}

# Check if node has running pods (excluding system pods)
has_workload_pods() {
    local node=$1
    local pod_count=$(kubectl get pods --all-namespaces --field-selector spec.nodeName="$node" \
        --no-headers | grep -v -E "(kube-system|karpenter)" | wc -l)
    [[ $pod_count -gt 0 ]]
}

# Wait for new node to be ready
wait_for_replacement() {
    local initial_count=$(kubectl get nodes -l "$NODEPOOL_LABEL" --no-headers | wc -l)
    local timeout=300
    local elapsed=0
    
    log "Waiting for replacement node (timeout: ${timeout}s)"
    
    while [[ $elapsed -lt $timeout ]]; do
        local current_count=$(kubectl get nodes -l "$NODEPOOL_LABEL" --no-headers | wc -l)
        if [[ $current_count -gt $initial_count ]]; then
            log "Replacement node detected"
            sleep 30  # Allow node to fully initialize
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log "ERROR: Timeout waiting for replacement node"
    return 1
}

# Main execution
main() {
    log "Starting controlled node replacement"
    
    check_maintenance_window
    
    local target_node=$(get_oldest_node)
    if [[ -z "$target_node" ]]; then
        log "No nodes found older than $MIN_NODE_AGE_HOURS hours with label $NODEPOOL_LABEL"
        exit 0
    fi
    
    log "Target node: $target_node"
    
    # Cordon the node
    log "Cordoning node: $target_node"
    kubectl cordon "$target_node"
    
    # Check if node has workload pods
    if has_workload_pods "$target_node"; then
        log "Node has workload pods, initiating drain"
        
        # Drain with PDB respect
        kubectl drain "$target_node" \
            --ignore-daemonsets \
            --delete-emptydir-data \
            --force \
            --timeout="$DRAIN_TIMEOUT" \
            --grace-period=30
        
        # Wait for replacement node
        if ! wait_for_replacement; then
            log "ERROR: Failed to get replacement node, uncordoning"
            kubectl uncordon "$target_node"
            exit 1
        fi
    fi
    
    # Delete the node (Karpenter will clean up the instance)
    log "Deleting node: $target_node"
    kubectl delete node "$target_node" --force --grace-period=0
    
    # Remove finalizers if node still exists
    if kubectl get node "$target_node" >/dev/null 2>&1; then
        log "Removing finalizers from node: $target_node"
        kubectl patch node "$target_node" -p '{"metadata":{"finalizers":[]}}' --type=merge
    fi
    
    log "Node replacement completed successfully"
}

main "$@"
