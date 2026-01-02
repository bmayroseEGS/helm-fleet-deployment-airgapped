# Elastic Stack Helm Charts for Air-gapped Deployment

This directory contains Helm charts for deploying the complete Elastic Stack (Elasticsearch, Kibana, and Logstash) to a Kubernetes cluster using images from a local container registry.

The `deploy.sh` script provides an interactive way to deploy all three components, or you can deploy each chart individually.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Namespace: elastic                     │ │
│  │                                                     │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │         StatefulSet: elasticsearch           │  │ │
│  │  │                                              │  │ │
│  │  │  ┌────────────┐  ┌────────────┐             │  │ │
│  │  │  │   Pod 1    │  │   Pod 2    │   ...       │  │ │
│  │  │  │            │  │            │             │  │ │
│  │  │  │  ES:9200   │  │  ES:9200   │             │  │ │
│  │  │  │  ES:9300   │  │  ES:9300   │             │  │ │
│  │  │  └─────┬──────┘  └─────┬──────┘             │  │ │
│  │  │        │               │                    │  │ │
│  │  │        └───────┬───────┘                    │  │ │
│  │  └────────────────┼────────────────────────────┘  │ │
│  │                   │                               │ │
│  │         ┌─────────┴─────────┐                     │ │
│  │         │                   │                     │ │
│  │  ┌──────▼───────┐    ┌─────▼──────┐              │ │
│  │  │  Service     │    │ Headless   │              │ │
│  │  │ ClusterIP    │    │  Service   │              │ │
│  │  │   :9200      │    │ (StatefulSet)             │ │
│  │  └──────────────┘    └────────────┘              │ │
│  │                                                   │ │
│  │  ┌──────────────────────────────────────┐        │ │
│  │  │  PersistentVolumeClaims (PVC)        │        │ │
│  │  │  - data-elasticsearch-master-0       │        │ │
│  │  │  - data-elasticsearch-master-1       │        │ │
│  │  └──────────────────────────────────────┘        │ │
│  └───────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                         │
                         │ pulls images from
                         ▼
              ┌──────────────────────┐
              │  Local Registry      │
              │  localhost:5000      │
              │                      │
              │  - elasticsearch:9.2.2│
              │  - kibana:9.2.2      │
              │  - logstash:9.2.2    │
              └──────────────────────┘
```

## Prerequisites

1. **Kubernetes cluster** - Running and accessible via kubectl
2. **Helm 3.x** - Installed and configured
3. **Local registry** - Running with Elasticsearch images loaded (see [../epr_deployment](../epr_deployment))
4. **kubectl access** - Configured to access your cluster

## Quick Start

### 1. Deploy using the script (Interactive)

```bash
cd helm_charts
./deploy.sh
```

The script will:
- Check prerequisites (kubectl, helm, cluster access)
- Verify local registry is accessible
- Create namespace
- **Interactively prompt** to deploy each component:
  - Deploy Elasticsearch? (y/n)
  - Deploy Kibana? (y/n)
  - Deploy Logstash? (y/n)
- Deploy selected components
- Wait for pods to be ready
- Display status and access instructions

### 2. Manual Deployment

```bash
# Create namespace
kubectl create namespace elastic

# Install Elasticsearch
helm install elasticsearch ./elasticsearch \
  --namespace elastic \
  --wait \
  --timeout 10m

# Install Kibana
helm install kibana ./kibana \
  --namespace elastic \
  --wait \
  --timeout 5m

# Install Logstash
helm install logstash ./logstash \
  --namespace elastic \
  --wait \
  --timeout 5m

# Check status
kubectl get pods -n elastic
```

## Dynamic Version Detection

The deployment script automatically detects image versions from your local registry, eliminating the need to manually update version numbers in `values.yaml` files.

**How it works:**
1. Script queries the local registry API at `localhost:5000`
2. Finds all available tags for each component's image
3. Automatically uses the latest version found in the registry
4. Falls back to `values.yaml` defaults if detection fails

**Benefits for air-gapped deployments:**
- No manual version updates needed
- Automatically uses whatever versions are loaded in your registry
- Works with mixed versions across different components
- Shows available images during prerequisites check

**Example output:**
```bash
[INFO] Available images in local registry:
  • elasticsearch: 9.2.2 9.2.1
  • kibana: 9.2.2
  • logstash: 9.2.2
  • elastic-agent/elastic-agent: 9.2.3
```

The script will automatically deploy using these detected versions, overriding the `tag` values in `values.yaml`.

## Configuration

Each component has its own `values.yaml` file for customization:

### Elasticsearch Configuration

Edit [elasticsearch/values.yaml](elasticsearch/values.yaml):

```yaml
image:
  registry: localhost:5000
  repository: elasticsearch
  tag: "9.2.2"

replicas: 1  # Scale to 3 for production

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

roles:
  - master  # Can be elected master
  - data    # Stores data
  - ingest  # Processes documents
```

### Kibana Configuration

Edit [kibana/values.yaml](kibana/values.yaml):

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

### Logstash Configuration

Edit [logstash/values.yaml](logstash/values.yaml):

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

persistence:
  enabled: true
  size: 10Gi

elasticsearchHosts: "http://elasticsearch-master:9200"
```

## Accessing Services

### Elasticsearch

**Port-forward Method (Development):**
```bash
# Forward port 9200 to localhost
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200

# In another terminal
curl http://localhost:9200
curl http://localhost:9200/_cluster/health?pretty
```

**NodePort Method (Testing):**
Edit elasticsearch/values.yaml:
```yaml
service:
  type: NodePort
  nodePort: 30920
```

Then upgrade:
```bash
helm upgrade elasticsearch ./elasticsearch -n elastic
```

Access via: `http://<node-ip>:30920`

### Kibana

**Port-forward from Local Machine (via SSH tunnel):**
```bash
# Step 1: Create SSH tunnel to remote server
ssh -i "your-key.pem" -L 5601:localhost:5601 user@your-server

# Step 2: Port-forward Kibana (on remote server)
kubectl port-forward -n elastic svc/kibana 5601:5601

# Step 3: Open browser on local machine
# http://localhost:5601
```

### Logstash

**Port-forward Method:**
```bash
# Forward HTTP input port
kubectl port-forward -n elastic svc/logstash 8080:8080

# Test HTTP input
curl -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"test log entry"}'
```

### LoadBalancer Method (Production)

For any service, edit its values.yaml:
```yaml
service:
  type: LoadBalancer
```

Get the external IP:
```bash
kubectl get svc -n elastic
```

## Scaling the Cluster

### Scale to 3 nodes (recommended for production)

```bash
helm upgrade elasticsearch ./elasticsearch \
  --namespace elastic \
  --set replicas=3 \
  --wait
```

Or edit values.yaml and set `replicas: 3`, then:

```bash
helm upgrade elasticsearch ./elasticsearch -n elastic
```

### Enable Multi-node Discovery

For multi-node clusters, edit values.yaml:

```yaml
esConfig:
  elasticsearch.yml: |
    cluster.name: ${CLUSTER_NAME}
    network.host: 0.0.0.0

    # Change from single-node to multi-node
    discovery.seed_hosts:
      - elasticsearch-master-headless
    cluster.initial_master_nodes:
      - elasticsearch-master-0
      - elasticsearch-master-1
      - elasticsearch-master-2
```

## Monitoring and Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n elastic -l app=elasticsearch
```

### View Logs
```bash
# All pods
kubectl logs -n elastic -l app=elasticsearch -f

# Specific pod
kubectl logs -n elastic elasticsearch-master-0 -f
```

### Check Cluster Health
```bash
# Port-forward first
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200

# Then check
curl http://localhost:9200/_cluster/health?pretty
curl http://localhost:9200/_cat/nodes?v
curl http://localhost:9200/_cat/indices?v
```

### Common Issues

#### Pod stuck in Pending
```bash
# Check events
kubectl describe pod -n elastic elasticsearch-master-0

# Common causes:
# - Insufficient resources
# - PVC not bound
# - Node selector constraints
```

#### CrashLoopBackOff
```bash
# Check logs
kubectl logs -n elastic elasticsearch-master-0

# Common causes:
# - vm.max_map_count too low (should be 262144)
# - Insufficient memory
# - Configuration errors
```

#### Can't pull image
```bash
# Verify registry is accessible from cluster nodes
# On each node:
curl http://localhost:5000/v2/_catalog

# Check if insecure registry is configured in Docker
# Edit /etc/docker/daemon.json on each node
```

## Customization Examples

### Custom JVM Heap Size

```yaml
esJavaOpts: "-Xmx4g -Xms4g"  # 4GB heap
resources:
  limits:
    memory: "8Gi"  # Should be 2x heap size
```

### Add Environment Variables

```yaml
extraEnvs:
  - name: CUSTOM_VAR
    value: "custom_value"
  - name: POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
```

### Node Affinity

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - elasticsearch
      topologyKey: kubernetes.io/hostname
```

## Uninstalling

```bash
# Remove the Helm release
helm uninstall elasticsearch -n elastic

# Optionally delete PVCs (WARNING: deletes data!)
kubectl delete pvc -n elastic -l app=elasticsearch

# Optionally delete namespace
kubectl delete namespace elastic
```

## Security Considerations

### Current Configuration (Development)

This chart is configured for development/testing with security disabled:
```yaml
xpack.security.enabled: false
```

### For Production

1. **Enable X-Pack Security**
```yaml
esConfig:
  elasticsearch.yml: |
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
```

2. **Set passwords** - Use elasticsearch-setup-passwords
3. **Enable TLS** - Configure certificates
4. **Network policies** - Restrict pod-to-pod traffic
5. **RBAC** - Limit service account permissions

## Next Steps

1. **Configure Backups** - Set up snapshot repository
2. **Enable Monitoring** - Use Elastic Stack monitoring
3. **Production Hardening** - Enable security, TLS, RBAC
4. **Add Beats** - Deploy Filebeat, Metricbeat for data collection
5. **Configure Ingress** - Set up ingress controllers for external access
6. **Scale Components** - Increase replicas for production workloads

## File Structure

```
helm_charts/
├── deploy.sh              # Interactive deployment script
│
├── elasticsearch/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── statefulset.yaml
│       ├── service.yaml
│       ├── configmap.yaml
│       └── NOTES.txt
│
├── kibana/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml
│       └── NOTES.txt
│
└── logstash/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── statefulset.yaml
        ├── service.yaml
        ├── configmap-config.yaml
        ├── configmap-pipeline.yaml
        └── NOTES.txt
```

## Support

For issues or questions:
1. Check the [troubleshooting section](#monitoring-and-troubleshooting)
2. Review Elasticsearch logs: `kubectl logs -n elastic -l app=elasticsearch`
3. Check Kubernetes events: `kubectl get events -n elastic`
