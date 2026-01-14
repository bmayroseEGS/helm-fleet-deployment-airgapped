# Quickstart Guide

This guide provides a streamlined workflow to get the Elastic Stack up and running in an air-gapped environment.

## Prerequisites

- Access to the target machine (EC2 instance or similar)
- SSH access configured
- Git installed

## Step-by-Step Workflow

### 1. Clone the Repository

```bash
git clone git@github.com:bmayroseEGS/helm-fleet-deployment-airgapped.git
cd helm-fleet-deployment-airgapped
```

### 2. Set Execute Permissions

```bash
chmod +x deployment_infrastructure/collect-all.sh \
  deployment_infrastructure/install-k3s-airgap.sh \
  deployment_infrastructure/setup-machine.sh \
  deployment_infrastructure/uninstall-k3s-complete.sh \
  epr_deployment/epr.sh \
  epr_deployment/nuke_registry.sh
```

### 3. Run Setup Script

```bash
./deployment_infrastructure/setup-machine.sh
```

When prompted, configure git with your credentials:
- **Name**: `<your-name>`
- **Email**: `<your-email@example.com>`

### 4. Collect Images

```bash
./deployment_infrastructure/collect-all.sh
```

Add the following images when prompted:

```
docker.elastic.co/elasticsearch/elasticsearch:9.2.2
docker.elastic.co/kibana/kibana:9.2.2
docker.elastic.co/logstash/logstash:9.2.2
registry:2
busybox:1.35
docker.elastic.co/elastic-agent/elastic-agent:9.2.3
```

### 5. Deploy EPR (Elastic Package Registry)

```bash
./epr_deployment/epr.sh
```

### 6. Install K3s

```bash
./deployment_infrastructure/install-k3s-airgap.sh
```

### 7. Deploy the Elastic Stack

```bash
./helm_charts/deploy.sh
```

**Note**: This will initially fail and timeout on the Fleet Server deployment because port forwarding needs to be configured. Don't worry - the Fleet Server will still be running.

Verify the deployment:

```bash
kubectl get all -n elastic
```

### 8. Configure Port Forwarding

Set up port forwarding to access the services:

```bash
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
kubectl port-forward -n elastic svc/kibana 5601:5601 &
kubectl port-forward -n elastic svc/logstash 8080:8080 &
kubectl port-forward -n elastic svc/fleet-server 8220:8220 &
```

**Alternative SSH Tunnel** (if accessing from a remote machine):

```bash
ssh -i "your_pemfile.pem" \
  -L 9200:localhost:9200 \
  -L 5601:localhost:5601 \
  -L 8080:localhost:8080 \
  -L 8220:localhost:8220 \
  ubuntu@<your-ec2-instance>
```

### 9. Complete Fleet Setup

Once port forwarding is configured, follow the instructions in [FLEET_SETUP.md](FLEET_SETUP.md) to complete the final configuration steps in Kibana.

## Access URLs

After port forwarding is configured, you can access:

- **Elasticsearch**: http://localhost:9200
- **Kibana**: http://localhost:5601
- **Logstash**: http://localhost:8080
- **Fleet Server**: http://localhost:8220

## Next Steps

Refer to [FLEET_SETUP.md](FLEET_SETUP.md) for detailed instructions on configuring Fleet in Kibana.
