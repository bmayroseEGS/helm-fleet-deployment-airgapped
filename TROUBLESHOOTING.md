# Troubleshooting Guide

Common issues and solutions for the Elastic Stack air-gapped deployment.

## Table of Contents

- [Registry Issues](#registry-issues)
- [Image Path Issues](#image-path-issues)
- [Kubernetes Deployment Issues](#kubernetes-deployment-issues)
- [Fleet Server Issues](#fleet-server-issues)

## Registry Issues

### Registry Not Accessible

**Symptoms:**
```
[WARN] Local registry at localhost:5000 may not be accessible
```

**Solution:**
```bash
# Check if registry is running
docker ps | grep elastic-registry

# If not running, restart it
cd epr_deployment
./epr.sh
```

### Registry Catalog Empty

**Symptoms:**
```
[INFO] Available images in local registry:
# No images listed
```

**Solution:**
```bash
# Reload images into registry
cd epr_deployment
./epr.sh
# Choose 'y' to restart registry
```

## Image Path Issues

### Nested Repository Path Not Preserved (Fixed in latest version)

**Symptoms:**
```
[WARN] Could not detect version from registry, using default from values.yaml
Error: ImagePullBackOff - image not found
```

**Cause:**
Image stored as `localhost:5000/elastic-agent:9.2.3` but Helm chart expects `localhost:5000/elastic-agent/elastic-agent:9.2.3`

**Solution (if using older version of epr.sh):**

Option 1 - Update to latest version:
```bash
# Pull latest code with fix
git pull

# Re-run epr.sh to reload images with correct paths
cd epr_deployment
./epr.sh
```

Option 2 - Manual retag:
```bash
# Pull image with flat path
docker pull localhost:5000/elastic-agent:9.2.3

# Tag with nested path
docker tag localhost:5000/elastic-agent:9.2.3 localhost:5000/elastic-agent/elastic-agent:9.2.3

# Push to registry
docker push localhost:5000/elastic-agent/elastic-agent:9.2.3

# Verify
curl -s http://localhost:5000/v2/elastic-agent/elastic-agent/tags/list | jq
```

### Wrong Image URL in collect-all.sh

**Symptoms:**
```
Error response from daemon: pull access denied for docker.elastic.co/r/elastic-agent/elastic-agent
```

**Cause:**
Incorrect image URL with extra `/r/` in the path

**Solution:**
```bash
# Edit the image list
cd deployment_infrastructure
vi images/image_urls.txt

# Change FROM:
docker.elastic.co/r/elastic-agent/elastic-agent:9.2.3

# Change TO:
docker.elastic.co/elastic-agent/elastic-agent:9.2.3

# Re-run collection
./collect-all.sh
```

**Correct Image URLs:**
- Elasticsearch: `docker.elastic.co/elasticsearch/elasticsearch:9.2.2`
- Kibana: `docker.elastic.co/kibana/kibana:9.2.2`
- Logstash: `docker.elastic.co/logstash/logstash:9.2.2`
- Fleet Server: `docker.elastic.co/elastic-agent/elastic-agent:9.2.3`
- Registry: `registry:2`

## Kubernetes Deployment Issues

### Pod ImagePullBackOff

**Symptoms:**
```bash
kubectl get pods -n elastic
# Shows: ImagePullBackOff or ErrImagePull
```

**Diagnosis:**
```bash
# Check pod details
kubectl describe pod -n elastic <pod-name>

# Look for image pull errors in Events section
```

**Common Causes:**

1. **Image not in registry**
   ```bash
   # Verify image exists
   curl -s http://localhost:5000/v2/_catalog | jq
   curl -s http://localhost:5000/v2/<image-name>/tags/list | jq
   ```

2. **Wrong image path in values.yaml**
   ```bash
   # Check Helm values
   helm get values -n elastic <release-name>
   ```

### Pod CrashLoopBackOff

**Symptoms:**
```bash
kubectl get pods -n elastic
# Shows: CrashLoopBackOff
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n elastic <pod-name> --tail=50

# Check pod events
kubectl describe pod -n elastic <pod-name>
```

**Common Causes:**

1. **Insufficient resources**
   - Check node resources: `kubectl top nodes`
   - Reduce resource requests in values.yaml

2. **Configuration error**
   - Check configmaps: `kubectl get cm -n elastic`
   - Verify Elasticsearch/Kibana URLs

3. **Storage issues**
   - Check PVCs: `kubectl get pvc -n elastic`
   - Verify storage class exists

### Helm Timeout During Deployment

**Symptoms:**
```
Error: INSTALLATION FAILED: context deadline exceeded
```

**Solution:**
```bash
# Increase timeout
helm install <name> <chart> --timeout 15m

# Or check what's taking so long
kubectl get events -n elastic --sort-by='.lastTimestamp'
kubectl get pods -n elastic -w
```

## Fleet Server Issues

### Fleet Server Not Starting

**Symptoms:**
```bash
kubectl get pods -n elastic -l app=fleet-server
# Shows: Pending, CrashLoopBackOff, or ImagePullBackOff
```

**Diagnosis:**
```bash
# Check pod status
kubectl describe pod -n elastic -l app=fleet-server

# Check logs
kubectl logs -n elastic -l app=fleet-server --tail=100
```

**Common Fixes:**

1. **Elasticsearch not ready**
   ```bash
   # Verify Elasticsearch is running
   kubectl get pods -n elastic -l app=elasticsearch

   # Test Elasticsearch connectivity
   kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200
   curl http://localhost:9200
   ```

2. **Kibana not ready**
   ```bash
   # Verify Kibana is running
   kubectl get pods -n elastic -l app=kibana

   # Check Kibana logs
   kubectl logs -n elastic -l app=kibana --tail=50
   ```

3. **Image path issue** (see [Image Path Issues](#image-path-issues))

### Fleet Server Won't Connect to Elasticsearch

**Symptoms:**
In Fleet Server logs:
```
Connection refused
Unable to connect to Elasticsearch
```

**Solution:**
```bash
# Test connectivity from Fleet Server pod
kubectl exec -it -n elastic <fleet-server-pod> -- curl http://elasticsearch-master:9200

# Check service exists
kubectl get svc -n elastic elasticsearch-master

# Verify endpoints
kubectl get endpoints -n elastic elasticsearch-master
```

### Fleet Server Configuration in Kibana

**Symptoms:**
Fleet settings in Kibana show disconnected Fleet Server

**Solution:**

1. Access Kibana:
   ```bash
   kubectl port-forward -n elastic svc/kibana 5601:5601
   # Open: http://localhost:5601
   ```

2. Configure Fleet:
   - Navigate to: Management → Fleet → Settings
   - Fleet Server URL: `http://fleet-server:8220`
   - Click "Save and apply settings"

3. Verify Fleet Server status:
   ```bash
   kubectl port-forward -n elastic svc/fleet-server 8220:8220
   curl http://localhost:8220/api/status
   ```

## General Debugging Commands

### Check All Resources
```bash
# All resources in namespace
kubectl get all -n elastic

# Detailed pod information
kubectl get pods -n elastic -o wide

# Events (last hour)
kubectl get events -n elastic --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top pods -n elastic
kubectl top nodes
```

### Check Helm Releases
```bash
# List releases
helm list -n elastic

# Get release values
helm get values -n elastic <release-name>

# Get release manifest
helm get manifest -n elastic <release-name>

# Release history
helm history -n elastic <release-name>
```

### Check Registry
```bash
# List all images
curl -s http://localhost:5000/v2/_catalog | jq

# List tags for an image
curl -s http://localhost:5000/v2/<image-name>/tags/list | jq

# Example: Check Fleet Server image
curl -s http://localhost:5000/v2/elastic-agent/elastic-agent/tags/list | jq
```

### Clean Up Failed Deployments
```bash
# Uninstall specific component
helm uninstall -n elastic <component-name>

# Delete stuck PVCs
kubectl delete pvc -n elastic -l app=<component-name>

# Delete stuck pods (if needed)
kubectl delete pod -n elastic <pod-name> --force --grace-period=0

# Clean everything and start fresh
helm uninstall -n elastic elasticsearch kibana logstash fleet-server
kubectl delete pvc -n elastic --all
kubectl delete namespace elastic
```

## Getting Help

If you encounter issues not covered here:

1. Check pod logs: `kubectl logs -n elastic <pod-name>`
2. Check pod events: `kubectl describe pod -n elastic <pod-name>`
3. Check Helm release: `helm get manifest -n elastic <release-name>`
4. Check recent events: `kubectl get events -n elastic --sort-by='.lastTimestamp'`

Include this information when seeking help or opening an issue.
