# EPR Deployment (Elastic Private Registry)

A two-script solution for deploying Elastic Stack in air-gapped environments using a local container registry.

## Common Repos for a elasticsearch deployment
    https://www.docker.elastic.co/
docker.elastic.co/elasticsearch/elasticsearch:9.2.2
docker.elastic.co/kibana/kibana:9.2.2
docker.elastic.co/logstash/logstash:9.2.2
registry:2

docker.elastic.co/elastic-agent/elastic-agent:9.2.2
docker.elastic.co/integrations/elastic-connectors:9.2.2

## Overview

This solution consists of two scripts:

1. **[collect-images.sh](collect-images.sh)** - Run on internet-connected machine to gather images
2. **[epr.sh](epr.sh)** - Run on air-gapped machine to deploy local registry and load images

## Architecture

```
Internet-Connected Machine          Air-Gapped Environment
┌──────────────────────┐           ┌──────────────────────┐
│  collect-images.sh   │           │      epr.sh          │
│                      │           │                      │
│  1. Prompts for URLs │           │  1. Deploy Registry  │
│  2. Pulls images     │──Transfer─▶  2. Load .tar files  │
│  3. Saves as .tar    │   USB/SCP │  3. Push to registry │
│                      │           │                      │
│  ./images/           │           │  localhost:5000/     │
│    ├─ image1.tar     │           │    ├─ image1:tag     │
│    ├─ image2.tar     │           │    └─ image2:tag     │
│    └─ image3.tar     │           │                      │
└──────────────────────┘           └──────────────────────┘
                                            │
                                            ▼
                                   ┌──────────────────┐
                                   │  Helm Deployments │
                                   │  (Elasticsearch,  │
                                   │   Kibana, Fleet)  │
                                   └──────────────────┘
```

## Prerequisites

### Internet-Connected Machine
- Docker installed and running
- Network access to pull images
- Sufficient disk space (images can be 500MB-2GB each)

### Air-Gapped Machine
- Docker installed and running
- Sufficient disk space for registry and images
- Ubuntu 24.04 (or similar Linux distro)

## Usage Guide

### Phase 1: Collect Images (Internet-Connected)

1. **Make script executable:**
   ```bash
   chmod +x collect-images.sh
   ```

2. **Run the collection script:**
   ```bash
   ./collect-images.sh
   ```

3. **Enter image URLs when prompted:**

   The script will prompt you for each image. Enter one URL per line:
   ```
   Image URL [1]: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
   [INFO] ✓ Added: docker.elastic.co/elasticsearch/elasticsearch:8.11.0

   Image URL [2]: docker.elastic.co/kibana/kibana:8.11.0
   [INFO] ✓ Added: docker.elastic.co/kibana/kibana:8.11.0

   Image URL [3]: docker.elastic.co/beats/elastic-agent:8.11.0
   [INFO] ✓ Added: docker.elastic.co/beats/elastic-agent:8.11.0

   Image URL [4]: registry:2
   [INFO] ✓ Added: registry:2

   Image URL [5]: [just press Enter here - don't type anything]
   [INFO] Finished collecting images.
   ```

   **Important:** When you're done entering images, just press Enter on an empty line.

4. **Output:**
   - Creates `./images/` directory with `.tar` files
   - Creates `image-list.txt` with the list of images

5. **Transfer to air-gapped system:**
   ```bash
   # Option 1: SCP (if limited network access)
   scp -r images/ user@airgapped-host:/path/to/epr_deployment/

   # Option 2: Create tarball for USB transfer
   tar -czf images.tar.gz images/ image-list.txt
   ```

### Phase 2: Deploy Registry (Air-Gapped)

1. **Ensure images directory is present:**
   ```bash
   ls -la images/
   # Should see .tar files
   ```

2. **Configure Docker for insecure registry:**
   ```bash
   sudo nano /etc/docker/daemon.json
   ```

   Add:
   ```json
   {
     "insecure-registries": ["localhost:5000"]
   }
   ```

   Restart Docker:
   ```bash
   sudo systemctl restart docker
   ```

3. **Make script executable:**
   ```bash
   chmod +x epr.sh
   ```

4. **Run the deployment script:**
   ```bash
   ./epr.sh
   ```

   The script will:
   - Check dependencies
   - Deploy Docker Registry on port 5000
   - Load all `.tar` files
   - Push images to local registry
   - Display registry contents

5. **Verify registry is running:**
   ```bash
   docker ps | grep elastic-registry
   curl http://localhost:5000/v2/_catalog
   ```

## Using the Registry

### With Helm Charts

Update your Helm values file or use `--set` flags:

```yaml
# values.yaml
image:
  repository: localhost:5000/elasticsearch
  tag: 8.11.0
  pullPolicy: Always
```

Or with `--set`:
```bash
helm install elasticsearch elastic/elasticsearch \
  --set image.repository=localhost:5000/elasticsearch \
  --set image.tag=8.11.0
```

### With Fleet

Reference images in your Fleet configuration:

```yaml
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: fleet-agent
spec:
  image: localhost:5000/elastic-agent:8.11.0
```

### Pulling Images Manually

```bash
docker pull localhost:5000/elasticsearch:8.11.0
```

## Common Elastic Stack Images

Here are common images you'll need for Elastic Stack deployment:

```bash
# Elasticsearch
docker.elastic.co/elasticsearch/elasticsearch:8.11.0

# Kibana
docker.elastic.co/kibana/kibana:8.11.0

# Fleet Server
docker.elastic.co/beats/elastic-agent:8.11.0

# APM Server
docker.elastic.co/apm/apm-server:8.11.0

# Logstash (if needed)
docker.elastic.co/logstash/logstash:8.11.0

# Beats (if needed)
docker.elastic.co/beats/filebeat:8.11.0
docker.elastic.co/beats/metricbeat:8.11.0
```

## Registry Management

### Start/Stop Registry
```bash
# Stop
docker stop elastic-registry

# Start
docker start elastic-registry

# Restart
docker restart elastic-registry
```

### View Registry Logs
```bash
docker logs elastic-registry
docker logs -f elastic-registry  # Follow logs
```

### Check Registry Contents
```bash
# List all repositories
curl http://localhost:5000/v2/_catalog

# List tags for a specific image
curl http://localhost:5000/v2/elasticsearch/tags/list
```

### Remove Registry
```bash
# Stop and remove container
docker stop elastic-registry
docker rm elastic-registry

# Remove volume (WARNING: deletes all images)
docker volume rm registry-data
```

### Backup Registry Data
```bash
# Backup the volume
docker run --rm \
  -v registry-data:/data \
  -v $(pwd):/backup \
  ubuntu tar -czf /backup/registry-backup.tar.gz /data

# Restore the volume
docker run --rm \
  -v registry-data:/data \
  -v $(pwd):/backup \
  ubuntu tar -xzf /backup/registry-backup.tar.gz -C /
```

## Troubleshooting

### Issue: "connection refused" when pushing images

**Solution:** Ensure registry container is running:
```bash
docker ps | grep elastic-registry
# If not running:
docker start elastic-registry
```

### Issue: "http: server gave HTTP response to HTTPS client"

**Solution:** Configure Docker daemon to allow insecure registry:
```bash
sudo nano /etc/docker/daemon.json
```
Add:
```json
{
  "insecure-registries": ["localhost:5000"]
}
```
Then restart Docker:
```bash
sudo systemctl restart docker
```

### Issue: Cannot pull images from registry in Kubernetes

**Solution:** If using Kubernetes, you may need to configure each node:
```bash
# On each Kubernetes node:
sudo nano /etc/docker/daemon.json
# Add the insecure registry configuration
sudo systemctl restart docker
```

### Issue: "no space left on device"

**Solution:** Check disk space and clean up unused Docker resources:
```bash
df -h
docker system prune -a
docker volume prune
```

### Issue: Image fails to load from .tar file

**Solution:** Verify .tar file integrity:
```bash
tar -tzf images/image-name.tar | head
# Should show file contents, not errors
```

## Advanced Options

### Load Images Only (Skip Registry Deployment)

If the registry is already running:
```bash
./epr.sh --load-only
```

### Custom Registry Port

Edit [epr.sh](epr.sh) and change:
```bash
REGISTRY_PORT="5000"  # Change to your desired port
```

Remember to update Docker insecure registry config accordingly.

### Enable Registry Web UI

Add a web UI for easier management:
```bash
docker run -d \
  --name registry-ui \
  -p 8080:80 \
  -e REGISTRY_URL=http://localhost:5000 \
  joxit/docker-registry-ui:latest
```

Access at: http://localhost:8080

## Security Considerations

### For Production Use

This setup uses an **insecure HTTP registry** which is suitable for:
- Air-gapped environments
- Internal development
- Testing purposes

For production, consider:

1. **Enable TLS/HTTPS:**
   ```bash
   docker run -d \
     --name elastic-registry \
     -p 5000:5000 \
     -v registry-data:/var/lib/registry \
     -v /path/to/certs:/certs \
     -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
     -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
     registry:2
   ```

2. **Enable Authentication:**
   ```bash
   # Create htpasswd file
   docker run --rm \
     --entrypoint htpasswd \
     httpd:2 -Bbn username password > auth/htpasswd

   # Run registry with auth
   docker run -d \
     --name elastic-registry \
     -p 5000:5000 \
     -v registry-data:/var/lib/registry \
     -v $(pwd)/auth:/auth \
     -e "REGISTRY_AUTH=htpasswd" \
     -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
     -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
     registry:2
   ```

3. **Network Isolation:**
   - Use Docker networks to isolate registry
   - Configure firewall rules
   - Limit access to specific IPs

## File Structure

```
epr_deployment/
├── collect-images.sh          # Script for image collection
├── epr.sh                     # Script for registry deployment
├── README.md                  # This file
├── image-list.txt            # Generated: List of collected images
└── images/                   # Generated: Directory of .tar files
    ├── elasticsearch-8.11.0.tar
    ├── kibana-8.11.0.tar
    └── elastic-agent-8.11.0.tar
```

## Learning Resources

### Understanding Docker Registry
- Official Registry Documentation: https://docs.docker.com/registry/
- Registry API Spec: https://docs.docker.com/registry/spec/api/

### Docker Save/Load
- `docker save`: Exports images to tar archive
- `docker load`: Imports images from tar archive
- `docker tag`: Creates alias for image
- `docker push`: Uploads image to registry

### Elastic Stack on Kubernetes
- Elastic Cloud on Kubernetes (ECK): https://www.elastic.co/guide/en/cloud-on-k8s/current/
- Fleet and Elastic Agent: https://www.elastic.co/guide/en/fleet/current/

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review Docker logs: `docker logs elastic-registry`
3. Verify network connectivity: `curl http://localhost:5000/v2/`
4. Check Docker daemon logs: `sudo journalctl -u docker`

## License

This project is maintained for internal use. Adapt as needed for your environment.
