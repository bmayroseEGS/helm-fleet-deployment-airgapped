# collect-all.sh - Complete Air-gapped Collection Tool

## Overview

`collect-all.sh` is an enhanced version of `collect-images.sh` that collects **both**:
1. Container images (Elasticsearch, Kibana, etc.)
2. k3s components (for Kubernetes installation)

This is the **recommended script** for complete air-gapped deployments.

## What It Collects

### Container Images
- Elastic Stack images (elasticsearch, kibana, logstash, etc.)
- Docker Registry image (`registry:2`)
- Any other container images you specify

### k3s Components (Optional)
- `k3s` binary (lightweight Kubernetes distribution)
- `k3s-airgap-images-amd64.tar.gz` (required container images for k3s)
- `install-k3s.sh` (installation script)
- `INSTALL-K3S.md` (installation instructions)

## Usage

### On Internet-Connected Machine

```bash
cd epr_deployment
./collect-all.sh
```

The script will:
1. Check prerequisites (Docker, internet, disk space)
2. Prompt for container image URLs
3. Pull and save each image as .tar file
4. Ask if you want to download k3s components
5. Display summary and next steps

### Example Session

```
Air-gapped Collection Tool
Collects container images and k3s components

========================================
Checking Prerequisites
========================================

[INFO] Docker: Docker version 24.0.7
[INFO] Available disk space: 45GB
[INFO] Internet connectivity: OK

========================================
Creating Output Directories
========================================

[INFO] Created: ./images (for container images)
[INFO] Created: ./k3s-files (for k3s components)

========================================
Collecting Container Image URLs
========================================

[INFO] Enter container image URLs (one per line)
[INFO] When finished, just press Enter on an empty line

Image URL [1]: docker.elastic.co/elasticsearch/elasticsearch:9.2.2
[INFO] ✓ Added: docker.elastic.co/elasticsearch/elasticsearch:9.2.2

Image URL [2]: docker.elastic.co/kibana/kibana:9.2.2
[INFO] ✓ Added: docker.elastic.co/kibana/kibana:9.2.2

Image URL [3]: registry:2
[INFO] ✓ Added: registry:2

Image URL [4]:

[INFO] Finished collecting images.
[INFO] Total images to collect: 3

========================================
Pulling and Saving Container Images
========================================

[INFO] [1/3] Pulling: docker.elastic.co/elasticsearch/elasticsearch:9.2.2
[INFO] [1/3] Saving to: ./images/docker.elastic.co_elasticsearch_elasticsearch_9.2.2.tar
[INFO] [1/3] ✓ Successfully saved

...

========================================
Downloading k3s Components
========================================

[INFO] k3s is a lightweight Kubernetes distribution
[INFO] These files are needed for air-gapped k3s installation

Download k3s components for version v1.30.0+k3s1? (y/n): y
[INFO] Downloading k3s binary...
[INFO] ✓ k3s binary downloaded
[INFO] Downloading k3s airgap images...
[INFO] ✓ k3s airgap images downloaded
[INFO] Downloading k3s install script...
[INFO] ✓ k3s install script downloaded
[INFO] ✓ Installation instructions created: INSTALL-K3S.md
```

## Output Structure

After running, you'll have:

```
epr_deployment/
├── collect-all.sh
├── images/                                    # Container images
│   ├── docker.elastic.co_elasticsearch_elasticsearch_9.2.2.tar
│   ├── docker.elastic.co_kibana_kibana_9.2.2.tar
│   └── registry_2.tar
└── k3s-files/                                 # k3s components
    ├── k3s                                    # k3s binary
    ├── k3s-airgap-images-amd64.tar.gz        # Required images
    ├── install-k3s.sh                         # Install script
    └── INSTALL-K3S.md                         # Instructions
```

## Transfer to Air-gapped Machine

### Option A: USB Drive
```bash
# Copy directories to USB
cp -r images/ k3s-files/ /media/usb/

# On air-gapped machine
cp -r /media/usb/images/ /media/usb/k3s-files/ ~/epr_deployment/
```

### Option B: SCP (limited network)
```bash
scp -r images/ k3s-files/ user@airgapped-machine:~/epr_deployment/
```

## Installation on Air-gapped Machine

### Step 1: Install k3s (if collected)

```bash
cd k3s-files
cat INSTALL-K3S.md  # Read full instructions

# Quick install:
sudo mkdir -p /var/lib/rancher/k3s/agent/images/
sudo cp k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/
INSTALL_K3S_SKIP_DOWNLOAD=true ./install-k3s.sh

# Configure kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

# Verify
kubectl get nodes
```

### Step 2: Configure k3s for Local Registry

```bash
sudo mkdir -p /etc/rancher/k3s

cat <<EOF | sudo tee /etc/rancher/k3s/registries.yaml
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
configs:
  "localhost:5000":
    tls:
      insecure_skip_verify: true
EOF

sudo systemctl restart k3s
```

### Step 3: Deploy Local Registry

```bash
cd ../epr_deployment
./epr.sh
# Registry will be deployed at localhost:5000 with all your images
```

### Step 4: Deploy Elastic Stack to Kubernetes

```bash
cd ../helm_charts
./deploy.sh
# Interactive prompts for:
# - Deploy Elasticsearch? (y/n)
# - Deploy Kibana? (y/n)
# - Deploy Logstash? (y/n)
# Selected components will be deployed to the 'elastic' namespace
```

## Common Image URLs

### Elastic Stack Core
```
docker.elastic.co/elasticsearch/elasticsearch:9.2.2
docker.elastic.co/kibana/kibana:9.2.2
docker.elastic.co/logstash/logstash:9.2.2
```

### Fleet Server & Elastic Agent
```
docker.elastic.co/elastic-agent/elastic-agent:9.2.3  # Used for Fleet Server
docker.elastic.co/beats/filebeat:9.2.2
docker.elastic.co/beats/metricbeat:9.2.2
```

### Required for Registry
```
registry:2
```

### Optional (for testing)
```
busybox:latest
nginx:latest
```

## Comparison: collect-all.sh vs collect-images.sh

| Feature | collect-images.sh | collect-all.sh |
|---------|------------------|----------------|
| Container images | ✅ | ✅ |
| k3s components | ❌ | ✅ |
| Installation docs | ❌ | ✅ |
| Re-runnable | ✅ | ✅ |
| Complete solution | Partial | Complete |
| Recommended for | Images only | Full deployment |

## Troubleshooting

### "Not enough disk space"
- Check available space: `df -h .`
- Clean up: `docker system prune -a`
- Need at least 20GB free

### "Failed to download k3s"
- Check internet: `ping github.com`
- Try again (GitHub might be temporarily down)
- Or skip k3s download and install manually later

### "Failed to pull image"
- Check image URL is correct
- Check Docker Hub/registry is accessible
- Some images require authentication

## Advanced Usage

### Specify Custom k3s Version

Edit the script and change:
```bash
K3S_VERSION="v1.30.0+k3s1"  # Change to desired version
```

### Skip k3s Download

When prompted:
```
Download k3s components for version v1.30.0+k3s1? (y/n): n
```

### Collect Only Specific Images

Just enter the images you need when prompted, skip the rest.

## See Also

- [collect-images.sh](collect-images.sh) - Simple image collection only
- [epr.sh](epr.sh) - Registry deployment script
- [../helm_charts/deploy.sh](../helm_charts/deploy.sh) - Kubernetes deployment
- [../DEPLOYMENT-WORKFLOW.md](../DEPLOYMENT-WORKFLOW.md) - Complete workflow guide
