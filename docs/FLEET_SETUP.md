# Fleet Server Setup Guide

Fleet Server requires manual configuration in Kibana before deployment. Follow these steps in order.

## Prerequisites

- Elasticsearch deployed and running
- Kibana deployed and running
- Access to Kibana UI (via port-forward)

## Step 1: Access Kibana

Port-forward Kibana to your local machine:

```bash
kubectl port-forward -n elastic svc/kibana 5601:5601
```

Then open http://localhost:5601 in your browser.

## Step 2: Log in to Kibana

- Username: `elastic`
- Password: `elastic`

## Step 3: Configure Fleet in Kibana

1. **Navigate to Fleet**
   - Click the hamburger menu (≡) in the top left
   - Scroll down and click **Management** → **Fleet**

2. **Fleet Server Setup**
   - Kibana will prompt you to add a Fleet Server
   - Click **Add Fleet Server**

3. **Configure Fleet Server Host**
   - Fleet Server Host: `http://fleet-server:8220`
   - Click **Save and Continue**

4. **Configure Elasticsearch Output**
   - Name: `default`
   - Hosts: `http://elasticsearch-master:9200`
   - Advanced YAML configuration:
     ```yaml
     ssl.verification_mode: none
     ```
   - Click **Save and apply settings**

5. **Generate Fleet Server Policy**
   - Kibana will automatically create a `fleet-server-policy`
   - This policy is required for Fleet Server to start

6. **Get Enrollment Token** (Optional - already configured via service token)
   - The service token created by the Elasticsearch hook job is already configured
   - Fleet Server will use `ELASTICSEARCH_SERVICE_TOKEN` from the Kubernetes secret

## Step 4: Deploy Fleet Server

Once Fleet is configured in Kibana, deploy Fleet Server:

```bash
cd /home/ubuntu/helm-fleet-deployment/helm_charts

# Deploy Fleet Server
helm install fleet-server ./fleet-server --namespace elastic

# Watch deployment
kubectl get pods -n elastic -w
```

## Step 5: Verify Fleet Server

Check Fleet Server status:

```bash
# Check pod status
kubectl get pods -n elastic -l app=fleet-server

# Check Fleet Server logs
kubectl logs -n elastic -l app=fleet-server -f

# Port-forward and test status endpoint
kubectl port-forward -n elastic svc/fleet-server 8220:8220
curl http://localhost:8220/api/status
```

Expected response when healthy:
```json
{"name":"fleet-server","status":"HEALTHY"}
```

## Step 6: Verify in Kibana

Return to Kibana Fleet UI:
- Navigate to **Management** → **Fleet** → **Fleet Server**
- You should see your Fleet Server listed as **Healthy**

## Troubleshooting

### Fleet Server stuck in "STARTING" state

**Symptom**: Logs show "Waiting on policy with Fleet Server integration: fleet-server-policy"

**Solution**: The Fleet Server policy hasn't been created in Kibana yet. Complete Step 3 above.

### Connection refused errors

**Symptom**: `dial tcp [::1]:9200: connect: connection refused`

**Solution**: Check that:
1. Elasticsearch is running: `kubectl get pods -n elastic -l app=elasticsearch`
2. Elasticsearch service exists: `kubectl get svc -n elastic elasticsearch-master`
3. DNS resolution works from Fleet Server pod:
   ```bash
   kubectl exec -n elastic fleet-server-0 -- nslookup elasticsearch-master
   ```

### Service token issues

**Symptom**: Authentication errors or "service token not found"

**Solution**: Check that the service token secret exists:
```bash
kubectl get secret fleet-server-token -n elastic -o yaml
```

If missing, the Elasticsearch hook job may have failed. Check:
```bash
kubectl get jobs -n elastic
kubectl logs -n elastic job/elasticsearch-create-fleet-token
```

## Production Considerations

### Security

1. **Enable TLS** for Fleet Server:
   - Generate TLS certificates
   - Update Fleet Server values to use HTTPS
   - Update Fleet Server host URL in Kibana to `https://fleet-server:8220`

2. **Rotate Service Tokens**:
   - Service tokens should be rotated regularly
   - Update the Kubernetes secret after rotation

3. **Disable Anonymous Access**:
   - Once all passwords are set and Fleet Server is running, disable anonymous authentication in Elasticsearch
   - Remove the anonymous authentication configuration from `elasticsearch/values.yaml`
   - Upgrade the Elasticsearch Helm release

### High Availability

For production, run multiple Fleet Server replicas:

```bash
helm upgrade fleet-server ./fleet-server --namespace elastic --set replicas=3
```

### Monitoring

Monitor Fleet Server health:

```bash
# Check all Fleet Servers
kubectl get pods -n elastic -l app=fleet-server

# View aggregated logs
kubectl logs -n elastic -l app=fleet-server --tail=100 -f

# Check resource usage
kubectl top pods -n elastic -l app=fleet-server
```
