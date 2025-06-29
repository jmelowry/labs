#!/usr/bin/env bash

function start_cluster() {
    echo starting cluster
    k3d cluster create --config k3d.yaml
}

function teardown_cluster() {
    echo "Tearing down cluster"
    k3d cluster delete prometheus-stack
}

function show_status() {
    echo "=== Current Status ==="
    if k3d cluster list | grep -q "prometheus-stack"; then
        echo "Cluster: Running"
        
        if kubectl get pods --context k3d-prometheus-stack 2>/dev/null >/dev/null; then
            local running_pods
            local total_pods
            running_pods=$(kubectl get pods --context k3d-prometheus-stack --no-headers 2>/dev/null | grep -c "Running")
            total_pods=$(kubectl get pods --context k3d-prometheus-stack --no-headers 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$running_pods" -gt 0 ] && [ "$running_pods" -eq "$total_pods" ]; then
                echo "Pods: $running_pods/$total_pods Running"
            else
                echo "Pods: $running_pods/$total_pods Ready (some pods may still be starting)"
            fi
        else
            echo "Pods: Unable to connect to cluster"
        fi
    else
        echo "Cluster: Stopped"
    fi
}

function verify_requirements() {
    if ! command -v k3d &> /dev/null; then
        echo "k3d missing"
        exit
    fi

    # is docker running
    if ! docker info &> /dev/null; then
        echo "Docker is not running"
        exit
    fi

    # does helm exist?
    if ! command -v helm &> /dev/null; then
        echo "Helm missing"
        exit
    fi
}

function render_helm_manifests() {
    if [ ! -f "./manifests/prometheus.yaml" ]; then
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo update
        kubectl config use-context k3d-prometheus-stack
        helm template prometheus-stack prometheus-community/kube-prometheus-stack -f ./manifests/prometheus-values.yaml > ./manifests/prometheus.yaml
    else
        echo "Using existing prometheus-values.yaml"
    fi
}

# function port_forward() {
#     echo "Port forwarding to localhost:9090"
#     kubectl port-forward svc/prometheus-operated 9090:9090 --context k3d-prometheus-stack &
#     echo "Port forwarding to localhost:3000"
#     kubectl port-forward svc/grafana 3000:80 --context k3d-prometheus-stack &
# }

case "${1:-status}" in
    start)
        verify_requirements
        start_cluster
        render_helm_manifests
        # port_forward
        exit 0
        ;;
    stop|teardown)
        teardown_cluster
        exit 0
        ;;
    status)
        show_status
        exit 0
        ;;
    *)
        echo "Usage: $0 [start|stop|status]"
        echo "  start: Start cluster and install helm chart"
        echo "  stop: Teardown cluster"
        echo "  status: Show current status (default)"
        exit 1
        ;;
esac
