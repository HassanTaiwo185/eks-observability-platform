#!/usr/bin/env bash
# Installs the monitoring stack on the current cluster:
#   - kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
#   - Blackbox Exporter (availability and latency checks)
set -euo pipefail

CHART_VERSION="92.13.1"
BLACKBOX_CHART_VERSION="11.20.2"   # NEW
NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Cluster: $(kubectl config current-context)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "Installing kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$SCRIPT_DIR/../helm/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

# NEW: Blackbox Exporter (installed after, because its ServiceMonitors
# need the CRDs that kube-prometheus-stack creates)
echo "Installing Blackbox Exporter..."
helm upgrade --install blackbox prometheus-community/prometheus-blackbox-exporter \
  --version "$BLACKBOX_CHART_VERSION" \
  --namespace "$NAMESPACE" \
  -f "$SCRIPT_DIR/../helm/blackbox-exporter-values.yaml" \
  --wait --timeout 5m

kubectl get pods -n "$NAMESPACE"