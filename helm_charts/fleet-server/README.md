# Fleet Server Helm Chart for Air-gapped Deployment

This Helm chart deploys Elastic Fleet Server to manage Elastic Agents in your Kubernetes cluster.

## What is Fleet Server?

Fleet Server is a component of the Elastic Stack that provides centralized management for Elastic Agents. It acts as a control plane that:
- Manages agent enrollment and configuration
- Distributes agent policies
- Collects agent status and metrics
- Provides secure communication between Kibana and Elastic Agents

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Namespace: elastic                     │ │
│  │                                                     │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │  StatefulSet: fleet-server                   │  │ │
│  │  │  • Pod: fleet-server-0                       │  │ │
│  │  │  • Image: localhost:5000/elastic-agent:9.2.2 │  │ │
│  │  │  • Port: 8220                                │  │ │
│  │  │  • Volume: 10Gi PVC                          │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  │                                                     │ │
│  │  Communicates with:                                 │ │
│  │  - elasticsearch-master (data storage)              │ │
│  │  - kibana (management UI)                           │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                         │
                         │ Manages
                         ↓
              ┌──────────────────────┐
              │   Elastic Agents     │
              │  (on various hosts)  │
              └──────────────────────┘
```

## Prerequisites

1. **Elasticsearch** - Running and accessible
2. **Kibana** - Running and accessible
3. **Local registry** - With `elastic-agent:9.2.2` image loaded
4. **kubectl** - Configured to access your cluster
5. **Helm 3.x** - Installed

## Quick Start

### Using deploy.sh (Recommended)

```bash
cd helm_charts
./deploy.sh
# When prompted: Deploy Fleet Server? (y/n): y
```

### Manual Deployment

```bash
helm install fleet-server ./fleet-server \
  --namespace elastic \
  --create-namespace \
  --wait \
  --timeout 10m

# Check status
kubectl get pods -n elastic -l app=fleet-server
```

## Configuration

Edit [values.yaml](values.yaml) to customize:

### Image Configuration
```yaml
image:
  registry: localhost:5000
  repository: elastic-agent
  tag: "9.2.2"
```

### Resources
```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"
```

### Fleet Server Settings
```yaml
fleetServer:
  enabled: true
  port: 8220
  insecure: true  # Set to false for production with TLS

elasticsearchHosts: "http://elasticsearch-master:9200"
kibanaHosts: "http://kibana:5601"
```

## Accessing Fleet Server

### Port-forward Method

```bash
# Port-forward Fleet Server
kubectl port-forward -n elastic svc/fleet-server 8220:8220

# Check status
curl http://localhost:8220/api/status
```

### Configure in Kibana

1. **Access Kibana**:
   ```bash
   kubectl port-forward -n elastic svc/kibana 5601:5601
   # Open browser: http://localhost:5601
   ```

2. **Navigate to Fleet**:
   - Go to Management → Fleet → Settings
   - Set Fleet Server URL: `http://fleet-server:8220`
   - Click "Save and apply settings"

3. **Generate Enrollment Token**:
   - Go to Fleet → Agent policies
   - Select or create a policy
   - Click "Add agent"
   - Copy the enrollment token

## Deploying Elastic Agents

Once Fleet Server is configured, you can deploy Elastic Agents:

### On Kubernetes

```yaml
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: elastic-agent
  namespace: elastic
spec:
  version: 9.2.2
  elasticsearchRefs:
  - name: elasticsearch
  image: localhost:5000/elastic-agent:9.2.2
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: elastic-agent
        containers:
        - name: agent
          env:
          - name: FLEET_URL
            value: http://fleet-server:8220
          - name: FLEET_ENROLLMENT_TOKEN
            value: "YOUR_ENROLLMENT_TOKEN"
```

### On External Hosts

```bash
# Using enrollment token from Kibana
sudo elastic-agent enroll \
  --url=http://fleet-server:8220 \
  --enrollment-token=YOUR_ENROLLMENT_TOKEN

sudo elastic-agent run
```

## Monitoring

### View Logs

```bash
# Fleet Server logs
kubectl logs -n elastic -l app=fleet-server -f

# Specific pod
kubectl logs -n elastic fleet-server-0 -f
```

### Check Pod Status

```bash
kubectl get pods -n elastic -l app=fleet-server
kubectl describe pod -n elastic fleet-server-0
```

### Fleet Server Metrics

```bash
# Port-forward
kubectl port-forward -n elastic svc/fleet-server 8220:8220

# Get metrics
curl http://localhost:8220/api/status
```

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n elastic fleet-server-0

# Common issues:
# - Elasticsearch not accessible
# - Kibana not accessible
# - Insufficient resources
```

### Fleet Server Not Connecting to Elasticsearch

```bash
# Verify Elasticsearch is accessible from Fleet Server pod
kubectl exec -it -n elastic fleet-server-0 -- curl http://elasticsearch-master:9200

# Check Fleet Server logs
kubectl logs -n elastic fleet-server-0 | grep -i elasticsearch
```

### Agents Not Enrolling

1. **Verify Fleet Server URL** in Kibana Fleet settings
2. **Check enrollment token** is valid
3. **Verify network connectivity** from agent to Fleet Server

## Security Considerations

### Current Configuration (Development)

This chart is configured for development/testing:
- Fleet Server runs in insecure mode (no TLS)
- No authentication required
- Runs as root (required for some agent operations)

### For Production

1. **Enable TLS**:
   ```yaml
   fleetServer:
     insecure: false
   ```
   Generate and configure certificates.

2. **Enable Authentication**:
   - Configure Elasticsearch security
   - Use service accounts
   - Secure enrollment tokens

3. **Network Policies**:
   - Restrict pod-to-pod traffic
   - Limit external access

## Uninstalling

```bash
# Remove Fleet Server
helm uninstall fleet-server -n elastic

# Optionally delete PVC
kubectl delete pvc -n elastic -l app=fleet-server
```

## Next Steps

1. **Configure Agent Policies** - Define what data agents should collect
2. **Add Integrations** - Install integration packages (System, Kubernetes, etc.)
3. **Deploy Agents** - Roll out agents to monitored systems
4. **Monitor Agent Health** - Track agent status in Kibana Fleet UI
5. **Configure Data Streams** - Set up data retention and ILM policies

## Resources

- [Fleet and Elastic Agent Documentation](https://www.elastic.co/guide/en/fleet/current/fleet-server.html)
- [Agent Policy Documentation](https://www.elastic.co/guide/en/fleet/current/agent-policy.html)
- [Integration Packages](https://www.elastic.co/integrations)
