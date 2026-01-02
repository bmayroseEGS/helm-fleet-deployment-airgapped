# Getting Started - Complete Setup Guide

Complete guide from fresh Ubuntu machine to deployed Elastic Stack (Elasticsearch, Kibana, Logstash) cluster.

## Overview

Three machines, five scripts, one complete solution:

```
┌─────────────────────────────────────────────────────────────────┐
│                        COMPLETE WORKFLOW                         │
└─────────────────────────────────────────────────────────────────┘

Fresh Ubuntu Machine → Internet Machine → Air-gapped Machine
        ↓                    ↓                    ↓
  setup-machine.sh    collect-all.sh    install-k3s-airgap.sh
                                         epr.sh
                                         deploy.sh
```

## Phase 0: Fresh Machine Setup (OPTIONAL)

If starting with a fresh Ubuntu machine, run the setup script first:

```bash
# Download and run setup script
curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/setup-machine.sh -o setup-machine.sh
chmod +x setup-machine.sh
./setup-machine.sh
```

**What it does:**
- ✅ Updates system packages
- ✅ Installs Docker
- ✅ Adds your user to docker group
- ✅ Configures Git (interactive prompts for name/email)
- ✅ Installs useful tools (curl, wget, jq, vim)
- ✅ Optionally clones your repository

**Interactive prompts:**
- Git username and email
- Upgrade packages?
- Install additional tools?
- Clone repository?

**After setup:**
```bash
# Activate Docker permissions
newgrp docker

# Or log out and back in

# Test Docker
docker run hello-world
```

---

## Phase 1: Collection (Internet-Connected Machine)

Once Docker is set up, collect images and k3s:

```bash
cd helm-fleet-deployment/deployment_infrastructure
./collect-all.sh
```

**Enter your images when prompted:**
```
Image URL [1]: docker.elastic.co/elasticsearch/elasticsearch:9.2.2
Image URL [2]: docker.elastic.co/kibana/kibana:9.2.2
Image URL [3]: docker.elastic.co/logstash/logstash:9.2.2
Image URL [4]: registry:2
Image URL [5]: [Press Enter]

Download k3s components? (y/n): y
```

**Output:**
- `images/` - All container .tar files (~1-2GB)
- `k3s-files/` - k3s components and scripts (~250MB)

---

## Phase 2: Transfer

Transfer directories to air-gapped machine:

### Option A: USB Drive
```bash
# Copy deployment_infrastructure folder to USB
cp -r deployment_infrastructure/ /media/usb/

# On air-gapped machine
cp -r /media/usb/deployment_infrastructure ~/helm-fleet-deployment/
```

### Option B: SCP (if limited network)
```bash
scp -r deployment_infrastructure/ user@airgapped:~/helm-fleet-deployment/
```

---

## Phase 3: Install Kubernetes (Air-gapped Machine)

### Step 1: Install k3s

```bash
cd ~/helm-fleet-deployment/deployment_infrastructure
./install-k3s-airgap.sh
```

This script automatically:
- ✅ Installs k3s binary and airgap images
- ✅ Configures kubeconfig with correct permissions
- ✅ Sets up KUBECONFIG environment variable
- ✅ Configures localhost:5000 registry support
- ✅ Restarts k3s with registry configuration
- ✅ Verifies installation

**Reload your shell:**
```bash
source ~/.bashrc
```

**Verify k3s:**
```bash
kubectl get nodes
# Should show: Ready control-plane,master
```

---

## Phase 4: Deploy Registry (Air-gapped Machine)

```bash
cd ~/helm-fleet-deployment/epr_deployment
./epr.sh
```

**What it does:**
- ✅ Configures Docker for insecure registry
- ✅ Starts Docker Registry at localhost:5000
- ✅ Loads all .tar files
- ✅ Pushes images to local registry
- ✅ Verifies registry accessibility

**Expected output:**
```
Registry URL: localhost:5000
Registry catalog shows: elasticsearch, kibana, logstash, registry
```

**Verify registry:**
```bash
curl http://localhost:5000/v2/_catalog
# Should show: {"repositories":["elasticsearch","kibana","logstash",...]}
```

---

## Phase 5: Deploy Elastic Stack (Air-gapped Machine)

```bash
cd ~/helm-fleet-deployment/helm_charts
./deploy.sh
```

**What it does:**
- ✅ Checks prerequisites (kubectl, helm, registry)
- ✅ Creates 'elastic' namespace
- ✅ **Interactively prompts** for each component:
  - Deploy Elasticsearch? (y/n)
  - Deploy Kibana? (y/n)
  - Deploy Logstash? (y/n)
- ✅ Deploys selected Helm charts
- ✅ Waits for pods to be ready
- ✅ Displays status and access instructions

**Expected output:**
```
NAME                       READY   STATUS    AGE
elasticsearch-master-0     1/1     Running   2m
kibana-xxxxxxxxxx          1/1     Running   1m
logstash-0                 1/1     Running   1m
```

---

## Phase 6: Access Services

### Elasticsearch

```bash
# Port-forward (keep this running)
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200
```

**In another terminal:**
```bash
# Test connection
curl http://localhost:9200

# Check cluster health
curl http://localhost:9200/_cluster/health?pretty

# Expected output:
{
  "cluster_name" : "elasticsearch",
  "status" : "green",
  "number_of_nodes" : 1
}
```

### Kibana (from local machine)

```bash
# Step 1: Create SSH tunnel to remote server
ssh -i "your-key.pem" -L 5601:localhost:5601 user@your-server

# Step 2: Port-forward Kibana (on remote server)
kubectl port-forward -n elastic svc/kibana 5601:5601

# Step 3: Open browser on local machine
# http://localhost:5601
```

### Logstash

```bash
# Port-forward
kubectl port-forward -n elastic svc/logstash 8080:8080

# Test HTTP input (in another terminal)
curl -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"test log entry"}'
```

---

## Quick Reference: When to Use Each Script

| Script | Machine | Purpose | When to Run |
|--------|---------|---------|-------------|
| setup-machine.sh | Any Ubuntu | Initial setup | Once per machine |
| collect-all.sh | Internet | Collect images/k3s | Once (or when updating) |
| install-k3s-airgap.sh | Air-gapped | Install k3s | Once per cluster |
| epr.sh | Air-gapped | Deploy registry | Once per machine |
| deploy.sh | Air-gapped | Deploy Elastic Stack | Once per cluster |

## Troubleshooting

### Docker Permission Denied
```bash
# After setup-machine.sh, activate group
newgrp docker

# Or logout and login
```

### kubectl: Permission Denied
```bash
# Already fixed by install-k3s-airgap.sh, but if needed:
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

### Registry Not Accessible
```bash
# Check registry is running
docker ps | grep registry

# Check from k8s node
curl http://localhost:5000/v2/_catalog
```

### Pod Stuck in Pending
```bash
# Check events
kubectl describe pod -n elastic elasticsearch-master-0

# Check resources
kubectl top nodes
```

### Image Pull Errors
```bash
# Verify registry configuration
sudo cat /etc/rancher/k3s/registries.yaml

# Restart k3s
sudo systemctl restart k3s
```

---

## Complete Example Session

Here's what a complete setup looks like:

```bash
# === FRESH UBUNTU MACHINE ===
./setup-machine.sh
# Interactive: Enter git name/email, confirm installations
newgrp docker

# === INTERNET MACHINE ===
cd deployment_infrastructure
./collect-all.sh
# Interactive: Enter image URLs
# Output: images/ and k3s-files/

# Transfer deployment_infrastructure/ to air-gapped machine via USB or SCP

# === AIR-GAPPED MACHINE ===
# Install k3s
cd deployment_infrastructure
./install-k3s-airgap.sh
source ~/.bashrc
kubectl get nodes  # Verify

# Deploy registry
cd ../../epr_deployment
./epr.sh
curl http://localhost:5000/v2/_catalog  # Verify

# Deploy Elastic Stack
cd ../helm_charts
./deploy.sh
# Interactive prompts for Elasticsearch, Kibana, Logstash

# Access services
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
curl http://localhost:9200

# Access Kibana (via SSH tunnel)
ssh -i "your-key.pem" -L 5601:localhost:5601 user@your-server
kubectl port-forward -n elastic svc/kibana 5601:5601
# Browser: http://localhost:5601
```

---

## Cleanup

To remove everything and start fresh:

```bash
# Remove all Elastic Stack components
helm uninstall elasticsearch kibana logstash -n elastic
kubectl delete pvc -n elastic -l app=elasticsearch
kubectl delete pvc -n elastic -l app=logstash

# Remove registry
cd epr_deployment
./nuke_registry.sh

# Remove k3s
cd ../deployment_infrastructure/k3s-files
./uninstall-k3s-complete.sh
```

---

## Next Steps

After successful deployment:

1. **Scale Elasticsearch**
   ```bash
   helm upgrade elasticsearch ./elasticsearch -n elastic --set replicas=3
   ```

2. **Enable Security** - Configure X-Pack security, TLS

3. **Set up Monitoring** - Deploy Elastic monitoring stack

4. **Configure Backups** - Set up snapshot repository

5. **Add Beats** - Deploy Filebeat, Metricbeat for data collection

6. **Configure Ingress** - Set up ingress controllers for external access

---

## See Also

- [QUICK-START.md](QUICK-START.md) - Condensed workflow
- [SCRIPTS-REFERENCE.md](SCRIPTS-REFERENCE.md) - All scripts documented
- [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md) - Detailed architecture
- [README.md](README.md) - Project overview
