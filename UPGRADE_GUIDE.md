# Upstream Upgrade Guide

This guide explains how to safely upgrade this fork with changes from the upstream `prometheus-community/helm-charts` repository while preserving Lirvana's GCP Prometheus customizations.

## Pre-Upgrade Checklist

### 1. Backup Current State
```bash
# Create a backup branch
git checkout -b backup-$(date +%Y%m%d)
git push origin backup-$(date +%Y%m%d)

# Document current deployment
kubectl get pods -n monitor -o yaml > backup-pods-$(date +%Y%m%d).yaml
helm get values kube-prometheus-stack -n monitor > backup-values-$(date +%Y%m%d).yaml
```

### 2. Test Current Deployment
```bash
# Verify datasources are working
kubectl exec -n monitor $(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) \
  -c grafana -- curl -s -u admin:$(kubectl get secret -n monitor kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d) \
  "http://localhost:3000/api/datasources/uid/gcp-prometheus-dev/health"
```

## Upgrade Process

### Step 1: Fetch Upstream Changes
```bash
# Add upstream remote (if not already added)
git remote add upstream https://github.com/prometheus-community/helm-charts.git

# Fetch latest upstream changes
git fetch upstream

# Check available versions
git tag --list --sort=-version:refname "kube-prometheus-stack-*" | head -10
```

### Step 2: Create Upgrade Branch
```bash
# Create and switch to upgrade branch
git checkout -b upgrade-upstream-$(date +%Y%m%d)

# Note: Choose the target version (e.g., kube-prometheus-stack-61.7.2)
export TARGET_VERSION="kube-prometheus-stack-61.7.2"
echo "Upgrading to: $TARGET_VERSION"
```

### Step 3: Merge Upstream Changes
```bash
# Option A: Merge specific tag (recommended)
git merge $TARGET_VERSION

# Option B: Merge upstream main (use with caution)
# git merge upstream/main
```

### Step 4: Resolve Conflicts

#### Common Conflict Areas
1. **Chart.yaml** - Version and dependency changes
2. **values.yaml** - New configuration options
3. **templates/** - Template updates

#### Resolution Strategy
```bash
# For Chart.yaml conflicts
git checkout --theirs charts/kube-prometheus-stack/Chart.yaml

# For values.yaml conflicts  
git checkout --theirs charts/kube-prometheus-stack/values.yaml

# For template conflicts
git checkout --theirs charts/kube-prometheus-stack/templates/

# Keep our customizations
git checkout --ours customizations/
git checkout --ours LIRVANA_CUSTOMIZATIONS.md
git checkout --ours UPGRADE_GUIDE.md
```

### Step 5: Update Customizations

#### Review Breaking Changes
```bash
# Check changelog for breaking changes
git show $TARGET_VERSION:charts/kube-prometheus-stack/UPGRADE.md

# Compare values.yaml structure
diff -u charts/kube-prometheus-stack/values.yaml customizations/values/gcp-prometheus-base.yaml
```

#### Update Custom Values Files
Check if any of these sections changed in the new version:
- `grafana.extraContainers`
- `grafana.extraVolumes` 
- `grafana.additionalDataSources`
- `grafana.sidecar`

### Step 6: Test the Upgrade

#### Dry Run Deployment
```bash
# Test with dev configuration
helm upgrade kube-prometheus-stack ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/dev.yaml \
  --dry-run --debug
```

#### Deploy to Development
```bash
# Apply to development cluster first
gcloud config set project lirvana-labs-development
gcloud container clusters get-credentials us-west1-a-two --zone us-west1-a

helm upgrade kube-prometheus-stack ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/dev.yaml
```

#### Validate Deployment
```bash
# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitor --timeout=300s

# Check all containers are running
kubectl get pods -n monitor -l app.kubernetes.io/name=grafana

# Verify token refresher is working
kubectl logs -n monitor -l app.kubernetes.io/name=grafana -c grafana-token-refresher --tail=10

# Test datasource health
kubectl exec -n monitor $(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) \
  -c grafana -- curl -s -u admin:$(kubectl get secret -n monitor kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d) \
  "http://localhost:3000/api/datasources/uid/gcp-prometheus-dev/health"
```

### Step 7: Deploy to Production

#### Switch to Production
```bash
gcloud config set project lirvana-labs-production
gcloud container clusters get-credentials oregon-1 --zone us-west1-a
```

#### Deploy with Production Values
```bash
helm upgrade kube-prometheus-stack ./charts/kube-prometheus-stack \
  -n monitor \
  -f customizations/values/gcp-prometheus-base.yaml \
  -f customizations/values/prod.yaml
```

#### Validate Production
```bash
# Same validation steps as development
kubectl exec -n monitor $(kubectl get pod -n monitor -l app.kubernetes.io/name=grafana -o name) \
  -c grafana -- curl -s -u admin:$(kubectl get secret -n monitor kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d) \
  "http://localhost:3000/api/datasources/uid/gcp-prometheus-prod/health"
```

### Step 8: Finalize Upgrade

#### Commit and Push
```bash
# Commit the merge
git add .
git commit -m "Upgrade to upstream $TARGET_VERSION

- Merged upstream changes
- Preserved Lirvana GCP Prometheus customizations
- Tested in dev and prod environments"

# Push upgrade branch
git push origin upgrade-upstream-$(date +%Y%m%d)
```

#### Create Pull Request
1. Create PR to merge upgrade branch into main
2. Include testing results in PR description
3. Tag team members for review

#### Merge to Main
```bash
# After PR approval
git checkout main
git merge upgrade-upstream-$(date +%Y%m%d)
git push origin main

# Tag the release
git tag -a lirvana-$TARGET_VERSION -m "Lirvana customizations on $TARGET_VERSION"
git push origin lirvana-$TARGET_VERSION
```

## Rollback Procedure

### If Issues Are Discovered

#### Helm Rollback
```bash
# List releases
helm history kube-prometheus-stack -n monitor

# Rollback to previous release
helm rollback kube-prometheus-stack [REVISION] -n monitor
```

#### Git Rollback
```bash
# Revert to previous working state
git checkout main
git revert HEAD --no-edit
git push origin main
```

## Post-Upgrade Tasks

### 1. Update Documentation
- Update version references in README files
- Document any new configuration options
- Update troubleshooting guides if needed

### 2. Monitor Deployment
- Watch Grafana dashboards for any issues
- Monitor token refresher logs for several cycles
- Verify all datasources remain functional

### 3. Clean Up
```bash
# Delete upgrade branch after successful deployment
git branch -d upgrade-upstream-$(date +%Y%m%d)
git push origin --delete upgrade-upstream-$(date +%Y%m%d)

# Keep backup branch for a few weeks, then delete
```

## Automation Considerations

### Future Improvements
1. **CI/CD Pipeline**: Automate testing of upgrades
2. **Monitoring**: Set up alerts for failed token refreshes
3. **Backup Strategy**: Automated backup before upgrades
4. **Testing**: Automated health checks post-deployment

### Scheduled Upgrades
Consider setting up a monthly review of upstream changes to stay current with security updates and new features.
