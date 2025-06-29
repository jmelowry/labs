Observability Stack Lab
=======================

A local Kubernetes observability stack using k3d and Prometheus.

Usage:
------

Start the cluster and deploy Prometheus:
  ./lab.sh start

Stop and cleanup the cluster:
  ./lab.sh stop

Check cluster status:
  ./lab.sh status

What it does:
-------------
- Creates a k3d cluster with 1 server and 2 agent nodes
- Deploys Prometheus monitoring stack using Helm
- Includes a sample web application with load generator
- Automatically injects manifests into the cluster

Requirements:
-------------
- Docker (running)
- k3d
- helm
- kubectl