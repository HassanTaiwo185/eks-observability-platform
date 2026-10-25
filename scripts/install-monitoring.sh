#!/usr/bin/env bash
# Installs Prometheus, Grafana and Alertmanager (kube-prometheus-stack) on the current cluster.
set -euo pipefail

CHART_VERSION="92.13.1"
NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Cluster: $(kubectl config current-context)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$SCRIPT_DIR/../helm/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

kubectl get pods -n "$NAMESPACE"