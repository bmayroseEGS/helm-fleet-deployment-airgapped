# Scripts Reference Guide

Complete reference for all automation scripts in this project.

## Overview

This project includes several automation scripts to simplify air-gapped Elastic Stack deployment:

```
┌─────────────────────────────────────────────────────────────┐
│                     DEPLOYMENT SCRIPTS                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Collection → Transfer → Install k3s → Deploy Registry →   │
│                                        Deploy Elasticsearch │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Phase 0: Machine Setup Script (Optional)

### setup-machine.sh
**Location:** `deployment_infrastructure/setup-machine.sh`
**Purpose:** Initial setup for fresh Ubuntu machine

**What it does:**
- Updates system packages
- Installs Docker
- Configures Docker permissions
- Sets up Git configuration
- Installs useful tools (curl, wget, jq, vim)
- Optionally clones additional repositories

**Usage:**
```bash
cd deployment_infrastructure
./setup-machine.sh
```

**When to use:** On fresh Ubuntu installations before collecting images

---

## Phase 1: Collection Script (Internet-Connected Machine)

### collect-all.sh
**Location:** `deployment_infrastructure/collect-all.sh`
**Purpose:** Collect container images AND k3s components for air-gapped deployment

**What it does:**
- Interactively collects container image URLs
- Pulls and saves images as .tar files
- Downloads k3s binary, airgap images, and install scripts
- Includes automated installation and uninstall scripts
- Generates installation documentation

**Usage:**
```bash
cd deployment_infrastructure
./collect-all.sh
```

**Output:**
- `images/` - Container image .tar files
- `k3s-files/` - k3s components, installation, and uninstall scripts

**When to use:** Always - this is the single collection script for air-gapped deployment

---

## Phase 2: Kubernetes Installation Scripts (Air-gapped Machine)

### install-k3s-airgap.sh
**Location:** `deployment_infrastructure/install-k3s-airgap.sh` (copied to k3s-files/ by collect-all.sh)
**Purpose:** **AUTOMATED** k3s installation with all configurations

**What it does:**
- Copies k3s binary to system path
- Installs k3s with airgap images
- Configures kubeconfig with correct permissions
- Sets up KUBECONFIG environment variable
- Configures localhost:5000 registry support
- Restarts k3s and fixes permissions
- Verifies installation
- Displays next steps

**Usage:**
```bash
cd k3s-files
./install-k3s-airgap.sh
```

**Benefits:**
- Single command installation
- Handles all permission issues automatically
- No manual steps required
- Includes verification

**When to use:** **ALWAYS** for new k3s installations (recommended)

---

### uninstall-k3s-complete.sh
**Location:** `deployment_infrastructure/uninstall-k3s-complete.sh` (copied to k3s-files/ by collect-all.sh)
**Purpose:** **COMPLETE** removal of k3s and all related components

**What it does:**
- Removes all Helm releases (with confirmation)
- Deletes all Kubernetes resources and namespaces
- Uninstalls k3s service
- Removes all k3s configuration files
- Removes k3s data directories
- Removes k3s binaries
- Cleans up environment variables (KUBECONFIG)
- Removes network interfaces (cni0, flannel.1)
- Optionally flushes iptables rules
- Optionally removes kubectl and helm
- Verifies cleanup

**Usage:**
```bash
cd k3s-files
./uninstall-k3s-complete.sh
```

**Interactive prompts:**
- Confirm uninstall
- Remove Helm releases?
- Delete custom namespaces?
- Flush iptables rules?
- Remove kubectl and helm?

**When to use:**
- When you want to completely remove k3s
- Before reinstalling k3s
- When cleaning up test environments

---

## Phase 3: Registry Deployment Scripts (Air-gapped Machine)

### epr.sh
**Location:** `epr_deployment/epr.sh`
**Purpose:** Deploy Docker Registry and load container images

**What it does:**
- Checks prerequisites (Docker, images)
- Automatically configures Docker for insecure registry
- Starts Docker Registry container at localhost:5000
- Loads .tar files and pushes to registry
- Verifies registry is accessible
- Displays usage instructions with actual loaded images

**Usage:**
```bash
cd epr_deployment
./epr.sh
```

**Modes:**
- Full deployment (default)
- `--load-only` - Skip registry deployment, only load images

**When to use:** After k3s installation, before Kubernetes deployment

---

### nuke_registry.sh
**Location:** `epr_deployment/nuke_registry.sh`
**Purpose:** Complete cleanup of registry deployment

**What it does:**
- Stops and removes registry container
- Removes registry volume
- Removes loaded Docker images
- Shows summary

**Usage:**
```bash
cd epr_deployment
./nuke_registry.sh
```

**When to use:** When you want to clean up and start fresh

---

## Phase 4: Kubernetes Deployment Scripts

### deploy.sh
**Location:** `helm_charts/deploy.sh`
**Purpose:** Deploy Elastic Stack (Elasticsearch, Kibana, Logstash) to Kubernetes using Helm

**What it does:**
- Checks prerequisites (kubectl, helm, cluster access)
- Verifies registry accessibility
- Creates namespace
- **Interactively prompts** for each component:
  - Deploy Elasticsearch? (y/n)
  - Deploy Kibana? (y/n)
  - Deploy Logstash? (y/n)
- Deploys selected Helm charts
- Waits for pods to be ready
- Displays status and access instructions

**Usage:**
```bash
cd helm_charts
./deploy.sh
```

**When to use:** After registry is deployed and accessible

---

## Script Comparison

| Script | Purpose | Internet Required | Air-gapped | Auto | Interactive |
|--------|---------|------------------|------------|------|-------------|
| collect-all.sh | Collect images + k3s | ✅ Yes | ❌ No | ❌ No | ✅ Yes |
| install-k3s-airgap.sh | Install k3s | ❌ No | ✅ Yes | ✅ Yes | ⚠️ Minimal |
| uninstall-k3s-complete.sh | Remove k3s | ❌ No | ✅ Yes | ⚠️ Partial | ✅ Yes |
| epr.sh | Deploy registry | ❌ No | ✅ Yes | ✅ Yes | ⚠️ Minimal |
| nuke_registry.sh | Clean registry | ❌ No | ✅ Yes | ⚠️ Partial | ✅ Yes |
| deploy.sh | Deploy Elastic Stack | ❌ No | ✅ Yes | ⚠️ Partial | ✅ Yes |

## Recommended Workflow

### Complete Air-gapped Workflow

**On Internet-connected machine:**
```bash
0. cd deployment_infrastructure
   ./setup-machine.sh              (Optional: if fresh Ubuntu)

1. ./collect-all.sh
   → Creates: images/ and k3s-files/
```

**Transfer to air-gapped machine** (USB drive or limited network)

**On air-gapped machine:**
```bash
2. cd deployment_infrastructure
   ./install-k3s-airgap.sh
   → Installs k3s with registry support

3. cd ../../epr_deployment
   ./epr.sh
   → Deploys registry at localhost:5000

4. cd ../helm_charts
   ./deploy.sh
   → Interactively deploys Elasticsearch, Kibana, Logstash to Kubernetes
```

### Cleanup Workflow

**Complete cleanup:**
```bash
1. helm uninstall elasticsearch kibana logstash -n elastic
   → Remove all Elastic Stack components

2. ./epr_deployment/nuke_registry.sh
   → Clean up registry

3. ./k3s-files/uninstall-k3s-complete.sh
   → Remove k3s completely
```

## Script Locations Summary

```
helm-fleet-deployment/
│
├── deployment_infrastructure/              ← START HERE: All setup and collection scripts
│   ├── setup-machine.sh            ← Phase 0: Fresh Ubuntu setup
│   ├── collect-all.sh              ← Phase 1: Collect images + k3s
│   ├── install-k3s-airgap.sh       ← Phase 2: k3s installation template
│   ├── uninstall-k3s-complete.sh   ← Cleanup: k3s uninstall template
│   ├── GETTING-STARTED.md          ← Complete workflow guide
│   ├── QUICK-START.md              ← Quick reference
│   ├── SCRIPTS-REFERENCE.md        ← This file
│   │
│   ├── images/                     (Generated by collect-all.sh)
│   │   └── *.tar                   ← Container image files
│   │
│   └── k3s-files/                  (Generated by collect-all.sh)
│       ├── k3s                     ← k3s binary
│       ├── k3s-airgap-images-amd64.tar.gz
│       ├── 
│       └── INSTALL-K3S.md          ← Installation instructions
│
├── epr_deployment/                  ← Phase 3: Registry deployment
│   ├── epr.sh                      ← Deploy local registry
│   └── nuke_registry.sh            ← Remove registry
│
└── helm_charts/                     ← Phase 4: Kubernetes deployment
    └── deploy.sh                   ← Deploy Elasticsearch
```

## Environment Variables

### KUBECONFIG
Set by: `install-k3s-airgap.sh`
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Removed by: `uninstall-k3s-complete.sh`

### Common Issues and Solutions

| Issue | Script | Solution |
|-------|--------|----------|
| Permission denied on kubectl | install-k3s-airgap.sh | Automatically fixes with chmod 644 |
| Registry not accessible | epr.sh | Automatically configures Docker |
| k3s won't start | install-k3s-airgap.sh | Check with: sudo systemctl status k3s |
| Can't connect to cluster | deploy.sh | Verify: kubectl get nodes |

## See Also

- [QUICK-START.md](QUICK-START.md) - Quick start guide
- [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md) - Complete workflow
- [epr_deployment/README.md](epr_deployment/README.md) - Registry docs
- [helm_charts/README.md](helm_charts/README.md) - Kubernetes docs
