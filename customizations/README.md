# Lirvana Labs Customizations

This directory contains all Lirvana-specific customizations for the `kube-prometheus-stack` Helm chart.

## Directory Structure

```
customizations/
├── README.md                          # This file
├── values/                            # Helm values files
│   ├── gcp-prometheus-base.yaml       # Base GCP configuration
│   ├── dev.yaml                       # Development environment
│   └── prod.yaml                      # Production environment
└── scripts/                           # Deployment and utility scripts
    ├── grafana-token-refresher.sh     # OAuth token refresher
    ├── deploy-dev.sh                  # Development deployment
    └── deploy-prod.sh                 # Production deployment
```

## Quick Start

### Development Deployment
```bash
# From repository root
./customizations/scripts/deploy-dev.sh
```

### Production Deployment
```bash
# From repository root
./customizations/scripts/deploy-prod.sh
```

### Manual Deployment
```bash
# Development
helm upgrade --install kube-prometheus-stack ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/dev.yaml

# Production
helm upgrade --install kube-prometheus-stack ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/prod.yaml
```

## Customization Overview

### 1. GCP Prometheus Integration
- **Base Configuration**: `values/gcp-prometheus-base.yaml`
- **Token Refresher**: `scripts/grafana-token-refresher.sh`
- **Sidecar Container**: Automatically refreshes OAuth tokens every 30 minutes

### 2. Environment-Specific Settings
- **Development**: Uses `lirvana-labs-development` project as default
- **Production**: Uses `lirvana-labs-production` project as default
- Both environments have access to both projects

### 3. Key Features
- ✅ Automated OAuth token refresh
- ✅ Workload Identity integration
- ✅ Multi-project support (dev/prod)
- ✅ Zero-downtime token updates
- ✅ Editable datasources via API

## Prerequisites

### GCP Setup
1. **Service Account**: `grafana@PROJECT-ID.iam.gserviceaccount.com`
2. **IAM Roles**:
   - `roles/monitoring.viewer`
   - `roles/monitoring.metricWriter` (if needed)
3. **Workload Identity**: Bound to Kubernetes service account

### Kubernetes Setup
1. **Namespace**: `monitor`
2. **Service Account**: `kube-prometheus-stack-grafana`
3. **Annotation**: `iam.gke.io/gcp-service-account: grafana@PROJECT-ID.iam.gserviceaccount.com`

## Validation

### Health Checks
```bash
# Check Grafana pods
kubectl get pods -n monitor -l app.kubernetes.io/name=grafana

# Check token refresher logs
kubectl logs -n monitor -l app.kubernetes.io/name=grafana -c grafana-token-refresher

# Test datasource health
kubectl exec -n monitor $(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) \
  -c grafana -- curl -s -u admin:PASSWORD \
  "http://localhost:3000/api/datasources/uid/gcp-prometheus-dev/health"
```

### Expected Results
- **Pod Status**: `4/4 Running` (grafana, 2x sidecar, token-refresher)
- **Token Refresher**: Logs show successful token updates every 30 minutes
- **Datasource Health**: `{"status":"OK","message":"Successfully queried the Prometheus API."}`

## Troubleshooting

### Common Issues

#### 1. Token Refresher Container Issues
```bash
# Check container image and logs
kubectl describe pod -n monitor -l app.kubernetes.io/name=grafana
kubectl logs -n monitor -l app.kubernetes.io/name=grafana -c grafana-token-refresher
```

#### 2. Workload Identity Problems
```bash
# Test OAuth token retrieval
kubectl exec -n monitor POD_NAME -c grafana -- \
  curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
```

#### 3. Datasource Issues
```bash
# Check datasource configuration
kubectl exec -n monitor POD_NAME -c grafana -- \
  curl -s -u admin:PASSWORD "http://localhost:3000/api/datasources"
```

### Debug Commands
```bash
# Get all monitoring resources
kubectl get all -n monitor

# Check ConfigMap
kubectl get configmap grafana-token-refresher-script -n monitor -o yaml

# Check service account annotations
kubectl get serviceaccount kube-prometheus-stack-grafana -n monitor -o yaml
```

## Maintenance

See the main repository documentation:
- [LIRVANA_CUSTOMIZATIONS.md](../LIRVANA_CUSTOMIZATIONS.md) - Overall strategy
- [UPGRADE_GUIDE.md](../UPGRADE_GUIDE.md) - Upgrade procedures

## Support

For issues related to these customizations, check:
1. Token refresher logs
2. Grafana datasource health endpoints
3. GCP IAM and Workload Identity configuration
4. Kubernetes service account annotations
