# Complete Air-gapped Elastic Stack Deployment Workflow

This guide shows the complete workflow from collecting images to deploying the full Elastic Stack (Elasticsearch, Kibana, and Logstash) on Kubernetes in an air-gapped environment.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT WORKFLOW                               │
└─────────────────────────────────────────────────────────────────────────┘

PHASE 1: Image Collection (Internet-connected Machine)
┌─────────────────────────────────────────────────────────────┐
│  Internet-connected Machine                                 │
│                                                             │
│  ┌──────────────────────────────────────────────┐          │
│  │  Run: ./collect-images.sh                    │          │
│  │                                               │          │
│  │  → Prompts for image URLs                    │          │
│  │  → Pulls from Docker Hub / Elastic registry  │          │
│  │  → Saves as .tar files                       │          │
│  └───────────────┬──────────────────────────────┘          │
│                  │                                          │
│                  ▼                                          │
│  ┌──────────────────────────────────────────────┐          │
│  │  Output: images/*.tar                        │          │
│  │  - elasticsearch-9.2.2.tar                   │          │
│  │  - kibana-9.2.2.tar                          │          │
│  │  - logstash-9.2.2.tar                        │          │
│  │  - registry-2.tar                            │          │
│  └───────────────┬──────────────────────────────┘          │
└──────────────────┼──────────────────────────────────────────┘
                   │
                   │ Transfer via USB/SCP
                   ▼

PHASE 2: Registry Deployment (Air-gapped Machine)
┌─────────────────────────────────────────────────────────────┐
│  Air-gapped Machine                                         │
│                                                             │
│  ┌──────────────────────────────────────────────┐          │
│  │  Run: ./epr.sh                               │          │
│  │                                               │          │
│  │  → Configures Docker insecure registry       │          │
│  │  → Starts Docker Registry container          │          │
│  │  → Loads .tar files into Docker              │          │
│  │  → Tags and pushes to localhost:5000         │          │
│  └───────────────┬──────────────────────────────┘          │
│                  │                                          │
│                  ▼                                          │
│  ┌──────────────────────────────────────────────┐          │
│  │  Docker Registry: localhost:5000             │          │
│  │  ┌────────────────────────────────────────┐  │          │
│  │  │  elasticsearch:9.2.2                   │  │          │
│  │  │  kibana:9.2.2                          │  │          │
│  │  │  logstash:9.2.2                        │  │          │
│  │  └────────────────────────────────────────┘  │          │
│  └───────────────┬──────────────────────────────┘          │
└──────────────────┼──────────────────────────────────────────┘
                   │
                   │ Images available at localhost:5000
                   ▼

PHASE 3: Kubernetes Deployment
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (same or different air-gapped machine)  │
│                                                             │
│  ┌──────────────────────────────────────────────┐          │
│  │  Run: ./deploy.sh                            │          │
│  │                                               │          │
│  │  → Checks prerequisites                      │          │
│  │  → Creates namespace                         │          │
│  │  → Prompts for each component:               │          │
│  │    • Deploy Elasticsearch? (y/n)             │          │
│  │    • Deploy Kibana? (y/n)                    │          │
│  │    • Deploy Logstash? (y/n)                  │          │
│  │  → Deploys selected Helm charts              │          │
│  │  → Waits for pods to be ready                │          │
│  └───────────────┬──────────────────────────────┘          │
│                  │                                          │
│                  ▼                                          │
│  ┌──────────────────────────────────────────────┐          │
│  │  Namespace: elastic                          │          │
│  │  ┌────────────────────────────────────────┐  │          │
│  │  │  StatefulSet: elasticsearch-master     │  │          │
│  │  │  ┌──────────────────────────────────┐  │  │          │
│  │  │  │  Pod: elasticsearch-master-0     │  │  │          │
│  │  │  │  Image: localhost:5000/          │  │  │          │
│  │  │  │         elasticsearch:9.2.2      │  │  │          │
│  │  │  │  Ports: 9200, 9300               │  │  │          │
│  │  │  │  Volume: 30Gi PVC                │  │  │          │
│  │  │  └──────────────────────────────────┘  │  │          │
│  │  └────────────────────────────────────────┘  │          │
│  │  ┌────────────────────────────────────────┐  │          │
│  │  │  Deployment: kibana                    │  │          │
│  │  │  ┌──────────────────────────────────┐  │  │          │
│  │  │  │  Pod: kibana-xxxxxxxxxx          │  │  │          │
│  │  │  │  Image: localhost:5000/          │  │  │          │
│  │  │  │         kibana:9.2.2             │  │  │          │
│  │  │  │  Port: 5601                      │  │  │          │
│  │  │  └──────────────────────────────────┘  │  │          │
│  │  └────────────────────────────────────────┘  │          │
│  │  ┌────────────────────────────────────────┐  │          │
│  │  │  StatefulSet: logstash                 │  │          │
│  │  │  ┌──────────────────────────────────┐  │  │          │
│  │  │  │  Pod: logstash-0                 │  │  │          │
│  │  │  │  Image: localhost:5000/          │  │  │          │
│  │  │  │         logstash:9.2.2           │  │  │          │
│  │  │  │  Port: 8080 (HTTP input)         │  │  │          │
│  │  │  │  Volume: 10Gi PVC                │  │  │          │
│  │  │  └──────────────────────────────────┘  │  │          │
│  │  └────────────────────────────────────────┘  │          │
│  │  ┌────────────────────────────────────────┐  │          │
│  │  │  Services:                             │  │          │
│  │  │  - elasticsearch-master (ClusterIP)    │  │          │
│  │  │  - elasticsearch-master-headless       │  │          │
│  │  │  - kibana (ClusterIP)                  │  │          │
│  │  │  - logstash (ClusterIP)                │  │          │
│  │  └────────────────────────────────────────┘  │          │
│  └──────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘

PHASE 4: Access Services
┌─────────────────────────────────────────────────────────────┐
│  Local Developer Machine                                    │
│                                                             │
│  SSH Tunnel + Port Forwarding                               │
│  ┌──────────────────────────────────────────────┐          │
│  │  Elasticsearch:                              │          │
│  │  kubectl port-forward svc/elasticsearch-     │          │
│  │    master 9200:9200                          │          │
│  │  → curl http://localhost:9200                │          │
│  │                                               │          │
│  │  Kibana (via SSH tunnel):                    │          │
│  │  ssh -L 5601:localhost:5601 user@server      │          │
│  │  kubectl port-forward svc/kibana 5601:5601   │          │
│  │  → Browser: http://localhost:5601            │          │
│  │                                               │          │
│  │  Logstash:                                    │          │
│  │  kubectl port-forward svc/logstash 8080:8080 │          │
│  │  → curl -X POST http://localhost:8080        │          │
│  └──────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

## Step-by-Step Workflow

### Prerequisites

**Internet-connected Machine:**
- Docker installed
- Internet access to Docker Hub and Elastic registries

**Air-gapped Machine:**
- Docker installed and running
- Kubernetes cluster (minikube, k3s, or full cluster)
- kubectl configured
- Helm 3.x installed

### Phase 1: Collect Images (Internet-connected)

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd helm-fleet-deployment/epr_deployment
   ```

2. **Run the collection script**
   ```bash
   ./collect-images.sh
   ```

3. **Enter image URLs when prompted**
   ```
   Image URL [1]: docker.elastic.co/elasticsearch/elasticsearch:9.2.2
   Image URL [2]: docker.elastic.co/kibana/kibana:9.2.2
   Image URL [3]: docker.elastic.co/logstash/logstash:9.2.2
   Image URL [4]: registry:2
   Image URL [5]: [press Enter to finish]
   ```

4. **Wait for completion**
   - Script will pull each image
   - Save as .tar files in `images/` directory
   - This may take 10-30 minutes depending on image sizes

5. **Verify output**
   ```bash
   ls -lh images/
   # Should show .tar files for each image
   ```

### Phase 2: Transfer Images

**Option A: USB Drive**
```bash
# Copy entire images directory to USB
cp -r images/ /media/usb/

# On air-gapped machine, copy back
cp -r /media/usb/images/ ~/helm-fleet-deployment/epr_deployment/
```

**Option B: SCP (if limited network access)**
```bash
scp -r images/ user@airgapped-machine:~/helm-fleet-deployment/epr_deployment/
```

### Phase 3: Deploy Registry (Air-gapped)

1. **Navigate to deployment directory**
   ```bash
   cd ~/helm-fleet-deployment/epr_deployment
   ```

2. **Verify images are present**
   ```bash
   ls -lh images/
   ```

3. **Run the EPR deployment script**
   ```bash
   ./epr.sh
   ```

4. **Follow prompts**
   - Configure Docker insecure registry (auto or manual)
   - Wait for registry to start
   - Wait for images to load and push

5. **Verify registry**
   ```bash
   curl http://localhost:5000/v2/_catalog
   # Should show: {"repositories":["elasticsearch","kibana","logstash"]}
   ```

### Phase 4: Deploy to Kubernetes

1. **Navigate to helm charts**
   ```bash
   cd ../helm_charts
   ```

2. **Review configuration** (optional)
   ```bash
   cat elasticsearch/values.yaml
   cat kibana/values.yaml
   cat logstash/values.yaml
   # Check registry URL, resources, replicas, etc.
   ```

3. **Deploy using script (interactive)**
   ```bash
   ./deploy.sh
   # Prompts:
   # Deploy Elasticsearch? (y/n): y
   # Deploy Kibana? (y/n): y
   # Deploy Logstash? (y/n): y
   ```

4. **Or deploy manually**
   ```bash
   # Deploy all components
   helm install elasticsearch ./elasticsearch \
     --namespace elastic \
     --create-namespace \
     --wait \
     --timeout 10m

   helm install kibana ./kibana \
     --namespace elastic \
     --wait \
     --timeout 5m

   helm install logstash ./logstash \
     --namespace elastic \
     --wait \
     --timeout 5m
   ```

5. **Verify deployment**
   ```bash
   kubectl get pods -n elastic
   kubectl get svc -n elastic
   kubectl get pvc -n elastic
   ```

### Phase 5: Access Services

1. **Access Elasticsearch**
   ```bash
   # Port-forward
   kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200

   # Test (in another terminal)
   curl http://localhost:9200
   curl http://localhost:9200/_cluster/health?pretty
   ```

   **Expected output**
   ```json
   {
     "cluster_name" : "elasticsearch",
     "status" : "green",
     "number_of_nodes" : 1,
     "number_of_data_nodes" : 1
   }
   ```

2. **Access Kibana (from local machine)**
   ```bash
   # Step 1: Create SSH tunnel
   ssh -i "your-key.pem" -L 5601:localhost:5601 user@your-server

   # Step 2: Port-forward Kibana (on remote server)
   kubectl port-forward -n elastic svc/kibana 5601:5601

   # Step 3: Open browser
   # http://localhost:5601
   ```

3. **Access Logstash**
   ```bash
   # Port-forward
   kubectl port-forward -n elastic svc/logstash 8080:8080

   # Test HTTP input (in another terminal)
   curl -X POST http://localhost:8080 \
     -H 'Content-Type: application/json' \
     -d '{"message":"test log entry"}'
   ```

## Directory Structure

```
helm-fleet-deployment/
├── deployment_infrastructure/      # Infrastructure setup
│   ├── collect-all.sh             # Phase 1: Collect all binaries & images
│   ├── install-k3s-airgap.sh      # Install k3s in air-gapped mode
│   ├── setup-machine.sh           # Initial machine setup
│   └── uninstall-k3s-complete.sh  # Complete k3s removal
│
├── epr_deployment/                 # Registry deployment
│   ├── epr.sh                     # Phase 2: Deploy registry
│   ├── nuke_registry.sh           # Cleanup script
│   ├── images/                    # Image .tar files (gitignored)
│   ├── README.md                  # EPR documentation
│   └── COLLECT-ALL-README.md      # Collection guide
│
├── helm_charts/                   # Kubernetes deployment
│   ├── deploy.sh                  # Phase 3: Deploy to K8s (interactive)
│   │
│   ├── elasticsearch/             # Elasticsearch Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── statefulset.yaml
│   │       ├── service.yaml
│   │       ├── configmap.yaml
│   │       └── NOTES.txt
│   │
│   ├── kibana/                    # Kibana Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── configmap.yaml
│   │       └── NOTES.txt
│   │
│   ├── logstash/                  # Logstash Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── statefulset.yaml
│   │       ├── service.yaml
│   │       ├── configmap-config.yaml
│   │       ├── configmap-pipeline.yaml
│   │       └── NOTES.txt
│   │
│   ├── README.md                  # Helm charts documentation
│   └── QUICKSTART.md              # Quick reference
│
├── DEPLOYMENT-WORKFLOW.md         # This file
└── README.md                      # Project overview
```

## Common Scenarios

### Scenario 1: Single Air-gapped Machine

If registry and Kubernetes are on the same machine:

1. Collect images on internet-connected machine
2. Transfer images to air-gapped machine
3. Run `./epr.sh` to deploy registry
4. Run `./deploy.sh` to deploy to Kubernetes
5. Access via port-forward

### Scenario 2: Separate Registry and Kubernetes

If Kubernetes cluster nodes need to access registry on different machine:

1. Collect images on internet-connected machine
2. Transfer to registry host
3. Run `./epr.sh` on registry host
4. Configure registry to be accessible from cluster nodes:
   ```bash
   # In epr.sh or docker run, change:
   docker run -d -p 5000:5000 ... # binds to all interfaces
   ```
5. Update `values.yaml` to use registry host IP:
   ```yaml
   image:
     registry: 192.168.1.10:5000  # Registry host IP
   ```
6. Configure insecure registry on all cluster nodes
7. Deploy to Kubernetes

### Scenario 3: Multiple Kubernetes Clusters

To deploy to multiple clusters using same registry:

1. Set up registry once (Phase 1-3)
2. For each cluster:
   ```bash
   # Switch kubectl context
   kubectl config use-context cluster-1

   # Deploy
   helm install elasticsearch ./elasticsearch -n elastic
   ```

## Troubleshooting

### Images not pulling from registry

**Check from cluster node:**
```bash
# SSH to cluster node
curl http://localhost:5000/v2/_catalog

# If fails, check Docker config
cat /etc/docker/daemon.json
# Should have: {"insecure-registries": ["localhost:5000"]}

# Restart Docker if needed
sudo systemctl restart docker
```

### Pod stuck in Pending

```bash
# Check events
kubectl describe pod -n elastic elasticsearch-master-0

# Common causes:
# 1. No available nodes with enough resources
# 2. PVC not bound - check storage class
# 3. Image pull errors - check registry accessibility
```

### Registry container not starting

```bash
# Check Docker logs
docker logs elastic-registry

# Check if port is already in use
netstat -tulpn | grep 5000

# Remove and restart
docker rm -f elastic-registry
./epr.sh
```

## Scaling and Production

### Scale to 3 nodes

```bash
helm upgrade elasticsearch ./elasticsearch \
  --namespace elastic \
  --set replicas=3
```

### Enable multi-node discovery

Edit `elasticsearch/values.yaml`:
```yaml
esConfig:
  elasticsearch.yml: |
    cluster.name: elasticsearch
    discovery.seed_hosts:
      - elasticsearch-master-headless
    cluster.initial_master_nodes:
      - elasticsearch-master-0
      - elasticsearch-master-1
      - elasticsearch-master-2
```

### Increase resources

Edit `elasticsearch/values.yaml`:
```yaml
resources:
  requests:
    memory: "4Gi"
  limits:
    memory: "8Gi"

esJavaOpts: "-Xmx4g -Xms4g"
```

## Maintenance

### Update images

1. Collect new images on internet-connected machine
2. Transfer to air-gapped machine
3. Run `./epr.sh --load-only` to add to existing registry
4. Update `values.yaml` with new tag
5. Upgrade deployment:
   ```bash
   helm upgrade elasticsearch ./elasticsearch -n elastic
   ```

### Backup and restore

```bash
# Backup PVCs
kubectl get pvc -n elastic
# Use your storage provider's snapshot feature

# Or backup via Elasticsearch snapshots
# Configure snapshot repository and use _snapshot API
```

### Clean up

```bash
# Remove Kubernetes deployment
helm uninstall elasticsearch -n elastic
kubectl delete pvc -n elastic -l app=elasticsearch

# Remove registry
cd epr_deployment
./nuke_registry.sh
```

## Next Steps

1. **Configure Ingress** - External access to services
2. **Enable Security** - X-Pack security, TLS, authentication
3. **Set up Monitoring** - Elastic Stack monitoring
4. **Configure Backups** - Snapshot repository for disaster recovery
5. **Add Beats** - Deploy Filebeat, Metricbeat for data collection
6. **Scale Components** - Increase replicas for production workloads

## Support and Documentation

- EPR Deployment: See [epr_deployment/README.md](epr_deployment/README.md)
- Helm Chart: See [helm_charts/README.md](helm_charts/README.md)
- Quick Starts:
  - [epr_deployment/QUICKSTART.md](epr_deployment/QUICKSTART.md)
  - [helm_charts/QUICKSTART.md](helm_charts/QUICKSTART.md)
