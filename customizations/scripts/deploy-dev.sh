#!/bin/bash

# Deploy kube-prometheus-stack to development environment
# Usage: ./deploy-dev.sh

set -e

echo "🚀 Deploying kube-prometheus-stack to Development Environment"

# Switch to development cluster
echo "📍 Switching to development cluster..."
gcloud config set project lirvana-labs-development
gcloud container clusters get-credentials us-west1-a-two --zone us-west1-a

# Create namespace if it doesn't exist
kubectl create namespace monitor --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap for token refresher script
echo "📦 Creating token refresher ConfigMap..."
kubectl create configmap grafana-token-refresher-script \
  --from-file=grafana-token-refresher.sh=customizations/scripts/grafana-token-refresher.sh \
  -n monitor --dry-run=client -o yaml | kubectl apply -f -

# Deploy Helm chart
echo "⚡ Deploying Helm chart..."
helm upgrade --install kube-prometheus-stack \
  ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/dev.yaml \
  --timeout 10m

# Wait for pods to be ready
echo "⏳ Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitor --timeout=300s

# Validate deployment
echo "🔍 Validating deployment..."
kubectl get pods -n monitor -l app.kubernetes.io/name=grafana

# Test token refresher
echo "🔧 Checking token refresher logs..."
kubectl logs -n monitor -l app.kubernetes.io/name=grafana -c grafana-token-refresher --tail=5 || echo "Token refresher not ready yet"

echo "✅ Development deployment completed!"
echo ""
echo "📝 Next steps:"
echo "   1. Wait a few minutes for token refresher to complete initial run"
echo "   2. Check datasource health with: kubectl exec -n monitor \$(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) -c grafana -- curl -s -u admin:tcf!WDW!pft7typ8jnk \"http://localhost:3000/api/datasources/uid/gcp-prometheus-dev/health\""
echo "   3. Access Grafana at: https://grafana.lirvanalabs.dev"
