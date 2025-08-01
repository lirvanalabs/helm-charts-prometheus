#!/bin/bash

# Deploy kube-prometheus-stack to production environment
# Usage: ./deploy-prod.sh

set -e

echo "🚀 Deploying kube-prometheus-stack to Production Environment"
echo "⚠️  WARNING: This will deploy to PRODUCTION. Continue? (y/N)"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Switch to production cluster
echo "📍 Switching to production cluster..."
gcloud config set project lirvana-labs-production
gcloud container clusters get-credentials oregon-1 --zone us-west1-a

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
  -f customizations/values/prod.yaml \
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

echo "✅ Production deployment completed!"
echo ""
echo "📝 Next steps:"
echo "   1. Wait a few minutes for token refresher to complete initial run"
echo "   2. Check datasource health with production admin credentials"
echo "   3. Monitor the deployment for any issues"
echo "   4. Access Grafana at: https://grafana.lirvanalabs.dev"
