# Lirvana Labs Helm Chart Customizations

This document describes the customizations made to the upstream `kube-prometheus-stack` Helm chart to support GCP Managed Prometheus with automated OAuth token refresh.

## Overview

This fork adds support for:
- GCP Managed Prometheus datasources in Grafana
- Automated OAuth token refresh using Workload Identity
- Seamless integration with multiple GCP projects (dev/prod)

## Fork Maintenance Strategy

### Repository Structure
```
├── charts/kube-prometheus-stack/           # Main Helm chart (upstream)
├── customizations/                         # Lirvana-specific files
│   ├── values/                            # Custom values files
│   │   ├── gcp-prometheus-base.yaml       # Base GCP configuration
│   │   ├── gcp-prometheus-config.yaml     # GCP Managed Prometheus monitoring
│   │   ├── dev.yaml                       # Development environment
│   │   └── prod.yaml                      # Production environment
│   ├── scripts/                           # Custom scripts
│   │   └── grafana-token-refresher.sh     # OAuth token refresher
│   ├── istio/                             # Istio configuration
│   │   └── grafana-virtualservice.yaml    # External access for Grafana
│   └── docs/                              # Documentation
├── LIRVANA_CUSTOMIZATIONS.md              # This file
└── UPGRADE_GUIDE.md                       # Upgrade procedures
```

### Upstream Integration

#### 1. Add Upstream Remote
```bash
git remote add upstream https://github.com/prometheus-community/helm-charts.git
git fetch upstream
```

#### 2. Branch Strategy
- `main` - Lirvana customizations on top of upstream
- `upstream-sync` - Clean upstream sync branch
- `feature/*` - Feature development branches

### Customization Categories

## 1. Core Customizations

### A. GCP Prometheus Integration
**Location**: `customizations/values/gcp-prometheus-base.yaml`
**Purpose**: Base configuration for GCP Managed Prometheus datasources

**Key Changes**:
- Datasource definitions with controlled UIDs
- OAuth token placeholder configuration
- Editable datasource settings

### B. Token Refresher Sidecar
**Location**: `customizations/scripts/grafana-token-refresher.sh`
**Purpose**: Automated OAuth token refresh for GCP authentication

**Features**:
- Fetches OAuth tokens from GCP metadata server
- Updates Grafana datasources via API
- Runs every 30 minutes
- No external dependencies (curl + sed only)

### C. Container Configuration
**Integration**: Added to Grafana `extraContainers` and `extraVolumes`

## 2. Environment-Specific Configurations

### Development Environment
**File**: `customizations/values/dev.yaml`
- Project: `lirvana-labs-development`
- Default datasource: GCP Prometheus Dev

### Production Environment  
**File**: `customizations/values/prod.yaml`
- Project: `lirvana-labs-production`
- Default datasource: GCP Prometheus Prod

## 3. File Organization

### Keep Separate from Upstream
These files should **never** be modified to avoid merge conflicts:
- `charts/kube-prometheus-stack/values.yaml` (upstream default)
- `charts/kube-prometheus-stack/templates/*` (upstream templates)
- `charts/kube-prometheus-stack/Chart.yaml` (upstream chart metadata)

### Customization Files
```
customizations/
├── values/
│   ├── gcp-prometheus-base.yaml    # Base GCP configuration
│   ├── dev.yaml                    # Dev-specific overrides
│   └── prod.yaml                   # Prod-specific overrides
├── scripts/
│   └── grafana-token-refresher.sh  # Token refresh script
└── templates/
    └── configmap-token-refresher.yaml  # ConfigMap template (if needed)
```

## 4. Infrastructure Components

### A. GCP Managed Prometheus Configuration
**File**: `customizations/values/gcp-prometheus-config.yaml`
**Purpose**: Configures metric collection from Kubernetes clusters to GCP Managed Prometheus

**Key Resources**:
- **PodMonitoring**: Collects metrics from kube-state-metrics, node-exporter, and Lirvana services
- **ServiceMonitor**: Collects metrics from Grafana itself
- **Namespace**: Creates `gmp-system` namespace for GCP Managed Prometheus

**Deploy with**:
```bash
kubectl apply -f customizations/values/gcp-prometheus-config.yaml
```

### B. Istio Integration
**File**: `customizations/istio/grafana-virtualservice.yaml`
**Purpose**: Exposes Grafana UI externally through Istio's ASM ingress gateway

**Configuration**:
- **Host**: `grafana.lirvanalabs.dev`
- **Gateway**: `asm-ingress/asm-ingressgateway`
- **Destination**: `kube-prometheus-stack-grafana` service
- **Timeout**: 300s for long-running queries

**Note**: The actual VirtualService is deployed from your main k8s repository at:
`/Users/allenchan/IdeaProjects/lirvana/k8s/development/istio/services/grafana.yaml`

The file here is for reference and consistency with this helm chart.

## 5. Deployment Commands

### Complete Development Deployment
```bash
# 1. Deploy GCP Managed Prometheus configuration
kubectl apply -f customizations/values/gcp-prometheus-config.yaml

# 2. Deploy Helm chart with Grafana and token refresher
helm upgrade --install kube-prometheus-stack \
  ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/dev.yaml

# 3. Deploy Istio VirtualService for external access
kubectl apply -f customizations/istio/grafana-virtualservice.yaml
```

### Complete Production Deployment
```bash
# 1. Deploy GCP Managed Prometheus configuration (prod version)
kubectl apply -f customizations/values/gcp-prometheus-config.yaml

# 2. Deploy Helm chart for production
helm upgrade --install kube-prometheus-stack \
  ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/prod.yaml

# 3. Deploy Istio VirtualService (same for both environments)
kubectl apply -f customizations/istio/grafana-virtualservice.yaml
```

## 6. Prerequisites

### GCP Setup
1. **Workload Identity** configured for the Grafana service account
2. **IAM Permissions** for the service account:
   - `monitoring.metricDescriptors.list`
   - `monitoring.metricDescriptors.get`
   - `monitoring.timeSeries.list`
   - `monitoring.projects.get`
   - `monitoring.viewer` role on both dev and prod projects

### Kubernetes Setup
1. **Namespace**: `monitor`
2. **Service Account**: `kube-prometheus-stack-grafana`
3. **Workload Identity Annotation**:
   ```yaml
   annotations:
     iam.gke.io/gcp-service-account: grafana-prometheus-reader@PROJECT-ID.iam.gserviceaccount.com
   ```
4. **GCP Managed Prometheus** enabled on clusters
5. **Istio/ASM** with ingress gateway configured

## 7. Validation

### Health Checks
```bash
# Check datasource health
kubectl exec -n monitor $(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) \
  -c grafana -- curl -s -u admin:PASSWORD \
  "http://localhost:3000/api/datasources/uid/gcp-prometheus-dev/health"

kubectl exec -n monitor $(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) \
  -c grafana -- curl -s -u admin:PASSWORD \
  "http://localhost:3000/api/datasources/uid/gcp-prometheus-prod/health"
```

### Token Refresher Logs
```bash
kubectl logs -n monitor -l app.kubernetes.io/name=grafana -c grafana-token-refresher --tail=20
```

## 8. Troubleshooting

### Common Issues
1. **401 Unauthorized**: Check Workload Identity configuration and IAM bindings
2. **Token Refresher Crashes**: Verify script permissions and container image
3. **Datasource Read-Only**: Ensure `editable: true` in configuration
4. **External Access Failed**: Verify Istio VirtualService and gateway configuration
5. **Metrics Not Collected**: Check GCP Managed Prometheus configuration and CRDs

### Debug Commands
```bash
# Test OAuth token retrieval
kubectl exec -n monitor POD_NAME -c grafana -- \
  curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"

# Test GCP API access
kubectl exec -n monitor POD_NAME -c grafana -- \
  curl -s -H "Authorization: Bearer TOKEN" \
  "https://monitoring.googleapis.com/v1/projects/PROJECT-ID/location/global/prometheus/api/v1/labels"

# Check Istio configuration
kubectl get virtualservice -n monitor grafana -o yaml
kubectl get gateway -n asm-ingress asm-ingressgateway -o yaml

# Verify GCP Managed Prometheus resources
kubectl get podmonitoring,servicemonitor -A
```

## Next Steps

1. ✅ Consolidated all monitoring configuration into helm chart repository
2. ✅ Created environment-specific values files with token refresher
3. Set up upstream remote and sync procedure
4. Document upgrade process in `UPGRADE_GUIDE.md`
5. Test complete deployment on staging environment
