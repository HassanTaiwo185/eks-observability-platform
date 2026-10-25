#!/usr/bin/env bash
# Installs the observability stack on the current EKS cluster:
#   - kube-prometheus-stack (Prometheus, Grafana, Alertmanager)  -> metrics
#   - Blackbox Exporter                                           -> availability and latency
#   - Fluent Bit                                                  -> logs to CloudWatch
#   - Grafana dashboards from dashboards/
set -euo pipefail

CLUSTER_NAME="cloudnative-eks"
NAMESPACE="monitoring"
CHART_VERSION="92.13.1"
BLACKBOX_CHART_VERSION="11.20.2"
FLUENT_BIT_CHART_VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Cluster: $(kubectl config current-context)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

# ---------- Metrics ----------
echo "Installing kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$SCRIPT_DIR/../helm/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

echo "Installing Blackbox Exporter..."
helm upgrade --install blackbox prometheus-community/prometheus-blackbox-exporter \
  --version "$BLACKBOX_CHART_VERSION" \
  --namespace "$NAMESPACE" \
  -f "$SCRIPT_DIR/../helm/blackbox-exporter-values.yaml" \
  --wait --timeout 5m

# ---------- Dashboards ----------
echo "Loading Grafana dashboards..."
for f in "$SCRIPT_DIR"/../dashboards/*.json; do
  name="dashboard-$(basename "$f" .json)"
  kubectl create configmap "$name" -n "$NAMESPACE" \
    --from-file="$f" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label configmap "$name" -n "$NAMESPACE" grafana_dashboard=1 --overwrite
done

# ---------- Logs ----------
# The Pod Identity association is deleted with the cluster, so recreate it if missing.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EXISTING=$(aws eks list-pod-identity-associations \
  --cluster-name "$CLUSTER_NAME" --namespace logging --service-account fluent-bit \
  --query 'associations[0].associationId' --output text)

if [ "$EXISTING" = "None" ] || [ -z "$EXISTING" ]; then
  echo "Creating Pod Identity association for Fluent Bit..."
  aws eks create-pod-identity-association \
    --cluster-name "$CLUSTER_NAME" --namespace logging --service-account fluent-bit \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/cloudnative-fluent-bit" >/dev/null
else
  echo "Pod Identity association already exists ($EXISTING)"
fi

echo "Installing Fluent Bit..."
helm upgrade --install fluent-bit eks/aws-for-fluent-bit \
  --version "$FLUENT_BIT_CHART_VERSION" \
  --namespace logging --create-namespace \
  -f "$SCRIPT_DIR/../helm/fluent-bit-values.yaml" \
  --wait --timeout 5m

kubectl get pods -n "$NAMESPACE"
kubectl get pods -n logging