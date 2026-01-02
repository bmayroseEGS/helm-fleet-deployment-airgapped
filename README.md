# Air-gapped Elastic Stack Deployment

Complete solution for deploying Elastic Stack (Elasticsearch, Kibana, Logstash, Fleet Server) in air-gapped Kubernetes environments using a local container registry.

## Overview

This project provides a complete workflow for deploying the full Elastic Stack in air-gapped environments:

1. **Infrastructure Setup** - Install k3s Kubernetes and essential tools (air-gapped)
2. **Image Collection** - Collect container images and binaries on internet-connected machine
3. **Registry Deployment** - Deploy local Docker registry and load images on air-gapped machine
4. **Stack Deployment** - Deploy Elasticsearch, Kibana, Logstash, and Fleet Server to Kubernetes using Helm charts

## Quick Start

### Phase 1: Collect Binaries & Images (Internet-connected machine)
```bash
cd deployment_infrastructure
./collect-all.sh
# Collects: k3s, Helm, container images
# Saves to: k3s-files/, helm-files/, ../epr_deployment/images/
```

### Phase 2: Transfer to Air-gapped Machine
```bash
# Transfer entire project directory to air-gapped machine
scp -r private-registry-elastic-deployment/ user@airgapped:/path/to/
```

### Phase 3: Setup Infrastructure (Air-gapped machine)
```bash
# Optional: Setup machine with essential tools
./deployment_infrastructure/setup-machine.sh

# Install k3s Kubernetes
./deployment_infrastructure/install-k3s-airgap.sh

# Deploy local Docker registry
cd epr_deployment
./epr.sh
# Registry deployed at localhost:5000 with all images loaded
```

### Phase 4: Deploy Elastic Stack
```bash
cd helm_charts
./deploy.sh
# Interactively prompts for:
# - Elasticsearch (y/n)
# - Kibana (y/n)
# - Logstash (y/n)
# - Fleet Server (y/n)
```

## Project Structure

```
.
├── deployment_infrastructure/      # Air-gapped deployment infrastructure
│   ├── collect-all.sh             # Collect all binaries and images
│   ├── install-k3s-airgap.sh      # Install k3s in air-gapped mode
│   ├── setup-machine.sh           # Initial machine setup
│   ├── uninstall-k3s-complete.sh  # Complete k3s removal
│   ├── GETTING-STARTED.md         # Getting started guide
│   ├── QUICK-START.md             # Quick reference
│   └── SCRIPTS-REFERENCE.md       # Scripts documentation
│
├── epr_deployment/                 # Elastic Private Registry deployment
│   ├── epr.sh                     # Deploy local Docker registry
│   ├── nuke_registry.sh           # Cleanup registry
│   ├── README.md                  # Registry documentation
│   ├── COLLECT-ALL-README.md      # Image collection guide
│   ├── .gitignore                 # Ignore images directory
│   └── images/                    # Container images (gitignored)
│
├── helm_charts/                    # Kubernetes Helm charts
│   ├── deploy.sh                  # Interactive deployment script
│   ├── README.md                  # Helm charts documentation
│   ├── QUICKSTART.md              # Quick reference
│   │
│   ├── elasticsearch/             # Elasticsearch Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── NOTES.txt
│   │       ├── configmap.yaml
│   │       ├── service.yaml
│   │       └── statefulset.yaml
│   │
│   ├── kibana/                    # Kibana Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── NOTES.txt
│   │       ├── configmap.yaml
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   ├── logstash/                  # Logstash Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── NOTES.txt
│   │       ├── configmap-config.yaml
│   │       ├── configmap-pipeline.yaml
│   │       ├── service.yaml
│   │       └── statefulset.yaml
│   │
│   └── fleet-server/              # Fleet Server Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── NOTES.txt
│           ├── configmap.yaml
│           ├── service.yaml
│           └── statefulset.yaml
│
├── DEPLOYMENT-WORKFLOW.md          # Complete workflow guide
└── README.md                       # This file
```

## Documentation

- **[DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md)** - Complete end-to-end workflow with architecture diagrams
- **[epr_deployment/README.md](epr_deployment/README.md)** - Registry deployment documentation
- **[helm_charts/README.md](helm_charts/README.md)** - Kubernetes/Helm deployment documentation

## Quick References

- **[epr_deployment/QUICKSTART.md](epr_deployment/QUICKSTART.md)** - Registry quick reference
- **[helm_charts/QUICKSTART.md](helm_charts/QUICKSTART.md)** - Kubernetes quick reference

## Features

### Registry Deployment (epr_deployment)
- Interactive image URL collection
- Automatic Docker insecure registry configuration
- Image loading and tagging for local registry
- Registry health verification
- Complete cleanup script

### Kubernetes Deployment (helm_charts)
- Production-ready Helm chart for Elasticsearch
- Configurable resources, replicas, and persistence
- StatefulSet with proper health checks
- Persistent storage with PVCs
- Single-node and multi-node cluster support
- Automated deployment script

## Prerequisites

**Internet-connected Machine:**
- Docker installed
- Internet access

**Air-gapped Machine:**
- Docker installed and running
- Kubernetes cluster (minikube, k3s, or production cluster)
- kubectl configured
- Helm 3.x installed

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Internet-Connected Machine                         │
│                                                                              │
│  deployment_infrastructure/collect-all.sh                                   │
│  ├── Downloads k3s binary + airgap images                                   │
│  ├── Downloads Helm binary                                                  │
│  └── Downloads Elastic Stack images (ES, Kibana, Logstash, Registry)        │
│                                                                              │
│  Output: k3s-files/, helm-files/, epr_deployment/images/                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ scp/rsync transfer
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Air-gapped Machine                                │
│                                                                              │
│  ┌────────────────────────┐    ┌──────────────────┐    ┌─────────────────┐ │
│  │ Infrastructure Setup   │    │ Registry Setup   │    │ Stack Deploy    │ │
│  │                        │    │                  │    │                 │ │
│  │ install-k3s-airgap.sh  │───→│ epr.sh           │───→│ deploy.sh       │ │
│  │ ├── Install k3s        │    │ ├── Start        │    │ ├── Elasticsearch│ │
│  │ ├── Setup kubectl      │    │ │   registry     │    │ ├── Kibana      │ │
│  │ └── Start cluster      │    │ └── Load images  │    │ └── Logstash    │ │
│  └────────────────────────┘    └──────────────────┘    └─────────────────┘ │
│                                                                              │
│  Kubernetes Cluster (k3s)          Docker Registry          Helm Charts     │
│  namespace: elastic                localhost:5000           Interactive     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ SSH tunnel + kubectl port-forward
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Local Developer Machine                           │
│                                                                              │
│  Browser: http://localhost:5601 → Kibana UI                                 │
│  curl http://localhost:9200      → Elasticsearch API                        │
│  curl http://localhost:8080      → Logstash HTTP input                      │
└─────────────────────────────────────────────────────────────────────────────┘
```
## After Cloning the Repo
```bash
# 1. Change the permissions for the scripts
chmod +x deployment_infrastructure/collect-all.sh deployment_infrastructure/install-k3s-airgap.sh deployment_infrastructure/setup-machine.sh deployment_infrastructure/uninstall-k3s-complete.sh epr_deployment/epr.sh epr_deployment/nuke_registry.sh
```
## Example Workflow

```bash
# 1. On internet-connected machine - collect everything
cd deployment_infrastructure
./collect-all.sh
# Script downloads:
# - k3s binary and images
# - Helm binary
# - Elasticsearch, Kibana, Logstash images
# - Docker registry image

# 2. Transfer entire project to air-gapped machine
scp -r private-registry-elastic-deployment/ user@airgapped:~/

# 3. On air-gapped machine - setup infrastructure
cd private-registry-elastic-deployment

# Install k3s
./deployment_infrastructure/install-k3s-airgap.sh
# k3s installed and running

# Deploy Docker registry with images
cd epr_deployment
./epr.sh
# Registry running at localhost:5000 with all images loaded

# 4. Deploy Elastic Stack
cd ../helm_charts
./deploy.sh
# Prompts:
# Deploy Elasticsearch? (y/n): y
# Deploy Kibana? (y/n): y
# Deploy Logstash? (y/n): y
# Deploy Fleet Server? (y/n): y

# 5. Verify deployment
kubectl get all -n elastic
# All pods should be Running

# 6. Access services
# Elasticsearch
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
curl http://localhost:9200

# Kibana (from local machine via SSH tunnel)
ssh -i "key.pem" -L 5601:localhost:5601 ubuntu@your-server
kubectl port-forward -n elastic svc/kibana 5601:5601
# Open browser: http://localhost:5601

# Logstash
kubectl port-forward -n elastic svc/logstash 8080:8080 &
curl -X POST http://localhost:8080 -H 'Content-Type: application/json' -d '{"message":"test"}'

# Fleet Server
kubectl port-forward -n elastic svc/fleet-server 8220:8220 &
curl http://localhost:8220/api/status
```

## Configuration

### Container Images
All components use images from the local registry at `localhost:5000`:
- Elasticsearch: `localhost:5000/elasticsearch:9.2.2`
- Kibana: `localhost:5000/kibana:9.2.2`
- Logstash: `localhost:5000/logstash:9.2.2`
- Fleet Server: `localhost:5000/elastic-agent/elastic-agent:9.2.3`

### Helm Chart Configuration

**Elasticsearch** - [helm_charts/elasticsearch/values.yaml](helm_charts/elasticsearch/values.yaml):
```yaml
image:
  registry: localhost:5000
  repository: elasticsearch
  tag: "9.2.2"

replicas: 1                 # Start with 1, scale to 3+

resources:
  requests:
    cpu: "1000m"
    memory: "2Gi"
  limits:
    cpu: "2000m"
    memory: "4Gi"

persistence:
  enabled: true
  size: 30Gi
```

**Kibana** - [helm_charts/kibana/values.yaml](helm_charts/kibana/values.yaml):
```yaml
image:
  registry: localhost:5000
  repository: kibana
  tag: "9.2.2"

replicas: 1

resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"

elasticsearchHosts: "http://elasticsearch-master:9200"
```

**Logstash** - [helm_charts/logstash/values.yaml](helm_charts/logstash/values.yaml):
```yaml
image:
  registry: localhost:5000
  repository: logstash
  tag: "9.2.2"

replicas: 1

resources:
  requests:
    cpu: "100m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"

elasticsearchHosts: "http://elasticsearch-master:9200"
```

**Fleet Server** - [helm_charts/fleet-server/values.yaml](helm_charts/fleet-server/values.yaml):
```yaml
image:
  registry: localhost:5000
  repository: elastic-agent/elastic-agent
  tag: "9.2.3"

replicas: 1

resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"

elasticsearchHosts: "http://elasticsearch-master:9200"
kibanaHosts: "http://kibana:5601"
```

## Scaling to Production

```bash
# Scale to 3 nodes
helm upgrade elasticsearch ./elasticsearch \
  --namespace elastic \
  --set replicas=3

# Increase resources
helm upgrade elasticsearch ./elasticsearch \
  --namespace elastic \
  --set resources.limits.memory=8Gi \
  --set esJavaOpts="-Xmx4g -Xms4g"
```

## Troubleshooting

For detailed troubleshooting information, see **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**.

### Quick Diagnostics

```bash
# Check all resources
kubectl get all -n elastic

# Check registry
curl http://localhost:5000/v2/_catalog

# View component logs
kubectl logs -n elastic -l app=elasticsearch -f
kubectl logs -n elastic -l app=kibana -f
kubectl logs -n elastic -l app=fleet-server -f

# Check events
kubectl get events -n elastic --sort-by='.lastTimestamp' | tail -20
```

Common issues:
- **Image not found**: See [TROUBLESHOOTING.md#image-path-issues](TROUBLESHOOTING.md#image-path-issues)
- **Pod won't start**: See [TROUBLESHOOTING.md#kubernetes-deployment-issues](TROUBLESHOOTING.md#kubernetes-deployment-issues)
- **Fleet Server issues**: See [TROUBLESHOOTING.md#fleet-server-issues](TROUBLESHOOTING.md#fleet-server-issues)

## Cleanup

```bash
# Remove individual components
helm uninstall elasticsearch -n elastic
helm uninstall kibana -n elastic
helm uninstall logstash -n elastic
helm uninstall fleet-server -n elastic

# Or remove all at once
helm uninstall elasticsearch kibana logstash fleet-server -n elastic

# Remove persistent volumes
kubectl delete pvc -n elastic -l app=elasticsearch

# Remove namespace (if desired)
kubectl delete namespace elastic

# Remove Docker registry
cd epr_deployment
./nuke_registry.sh

# Uninstall k3s completely (if desired)
cd ../deployment_infrastructure
./uninstall-k3s-complete.sh
```

## Deploying the Full Elastic Stack

The deployment script now supports deploying all three components: **Elasticsearch**, **Kibana**, and **Logstash**. The script will interactively prompt you before installing each component.

### Interactive Deployment

```bash
cd helm_charts
./deploy.sh
```

The script will ask you to confirm each component:
- **Deploy Elasticsearch?** (y/n) - Core search and analytics engine
- **Deploy Kibana?** (y/n) - Web UI for visualization and management
- **Deploy Logstash?** (y/n) - Data processing pipeline

You can choose to deploy all components or select specific ones based on your needs.

### Accessing Kibana from Your Local Machine

Once Kibana is deployed, you can access it from your local browser using SSH tunneling:

**Step 1: Create SSH Tunnel**
```bash
ssh -i "Brian_M_12_25.pem" -L 5601:localhost:5601 ubuntu@44.212.32.213
```

**Step 2: Port-forward Kibana Service (on remote server)**
```bash
kubectl port-forward -n elastic svc/kibana 5601:5601
```

**Step 3: Access in Browser**
Open your local browser and navigate to:
```
http://localhost:5601
```

The SSH tunnel forwards port 5601 from your local machine to the remote server, where kubectl port-forwards from the Kubernetes service to localhost on the server.

## Initial Setup Scripts

### Setup Script

Before deploying, run the setup script to prepare your machine and optionally clone additional repositories:

```bash
./deployment_infrastructure/setup-machine.sh
```

This script will:
- Install essential tools (git, curl, wget, etc.)
- Configure system settings for Kubernetes
- Prompt to clone other required repositories if needed
- Set up directory structure

### Installing Kubernetes (k3s)

Install k3s in air-gapped mode using the included script:

```bash
./deployment_infrastructure/install-k3s-airgap.sh
```

This script:
- Installs k3s from local binaries (no internet required)
- Configures kubeconfig at `/etc/rancher/k3s/k3s.yaml`
- Sets up kubectl symlink
- Starts k3s service
- Verifies cluster is running

**Note:** The install script requires k3s binaries collected by `collect-all.sh` in the `deployment_infrastructure/k3s-files/` directory.

### Collecting Additional Images

The `collect-all.sh` script can be **re-run multiple times** to add more container images to your collection:

```bash
cd deployment_infrastructure
./collect-all.sh
```

Each run will:
- Prompt for new image URLs
- Download and save images alongside existing ones
- Skip already-downloaded images
- Update the image list

This is useful when you need to:
- Add new Elastic Stack plugins
- Include additional monitoring tools
- Update to newer versions
- Add custom applications to your air-gapped environment

## Next Steps

1. Enable X-Pack security for production
2. Configure ingress for external access
3. Set up monitoring and alerting
4. Configure snapshot backups
5. Add Beats (Filebeat, Metricbeat) for data collection

## Support

For detailed information, see:
- [Complete Workflow Guide](DEPLOYMENT-WORKFLOW.md)
- [Registry Documentation](epr_deployment/README.md)
- [Helm Chart Documentation](helm_charts/README.md)

## License

This is an internal deployment tool. Elastic Stack components are subject to Elastic License.
