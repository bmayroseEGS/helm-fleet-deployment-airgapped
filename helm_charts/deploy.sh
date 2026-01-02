#!/bin/bash
################################################################################
# Elastic Stack Helm Deployment Script
# Purpose: Deploy Elasticsearch, Kibana, and Logstash to Kubernetes using local registry
################################################################################

set -e

# Get script directory to find helm-files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
HELM_FILES_DIR="$REPO_ROOT/deployment_infrastructure/helm-files"

# Change to script directory so relative paths work
cd "$SCRIPT_DIR"

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
NAMESPACE="elastic"
REGISTRY_URL="localhost:5000"

# Component configurations
declare -A COMPONENTS
COMPONENTS[elasticsearch]="./elasticsearch"
COMPONENTS[kibana]="./kibana"
COMPONENTS[logstash]="./logstash"
COMPONENTS[fleet-server]="./fleet-server"

################################################################################
# Function: install_helm_if_needed
################################################################################
install_helm_if_needed() {
    # Check if helm is already installed
    if command -v helm &> /dev/null; then
        local helm_ver=$(helm version --short 2>&1 | head -1 | tr -d '\r\n' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
        print_info "Helm is already installed: ${helm_ver}"
        return 0
    fi

    print_warning "Helm is not installed"

    # Check if we have the helm binary in helm-files
    if [ -f "$HELM_FILES_DIR/helm" ]; then
        print_info "Found Helm binary in $HELM_FILES_DIR"
        read -p "Install Helm from local files? (y/n): " install_helm

        if [[ "$install_helm" =~ ^[Yy]$ ]]; then
            print_info "Installing Helm to /usr/local/bin/helm..."
            sudo cp "$HELM_FILES_DIR/helm" /usr/local/bin/helm
            sudo chmod +x /usr/local/bin/helm

            # Verify installation
            if command -v helm &> /dev/null; then
                local helm_ver=$(helm version --short 2>&1 | head -1 | tr -d '\r\n' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
                print_info "✓ Helm installed successfully: ${helm_ver}"
                return 0
            else
                print_error "✗ Helm installation failed"
                exit 1
            fi
        else
            print_error "Helm is required for deployment"
            exit 1
        fi
    else
        print_error "Helm binary not found in $HELM_FILES_DIR"
        print_info "Please run collect-all.sh first to download Helm"
        print_info "Or install Helm manually: https://helm.sh/docs/intro/install/"
        exit 1
    fi
}

################################################################################
# Function: check_prerequisites
################################################################################
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    print_info "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

    # Install helm if needed
    install_helm_if_needed

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Make sure your kubeconfig is configured and cluster is accessible"
        exit 1
    fi
    print_info "Kubernetes cluster is accessible"

    # Check if registry is running
    if ! curl -s "http://${REGISTRY_URL}/v2/_catalog" &> /dev/null; then
        print_warning "Local registry at ${REGISTRY_URL} may not be accessible"
        print_info "Make sure the registry is running: docker ps | grep registry"
        read -p "Continue anyway? (y/n): " continue_deploy
        if [[ ! "$continue_deploy" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        print_info "Local registry is accessible at ${REGISTRY_URL}"

        # Display available images in registry
        echo ""
        print_info "Available images in local registry:"
        local catalog=$(curl -s "http://${REGISTRY_URL}/v2/_catalog" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$catalog" | jq -r '.repositories[]' 2>/dev/null | while read repo; do
                # Get tags for each repository
                local tags=$(curl -s "http://${REGISTRY_URL}/v2/${repo}/tags/list" 2>/dev/null | jq -r '.tags[]' 2>/dev/null | head -3)
                if [ -n "$tags" ]; then
                    echo "  • ${repo}: $(echo $tags | tr '\n' ' ')"
                fi
            done
        fi
    fi
}

################################################################################
# Function: create_namespace
################################################################################
create_namespace() {
    print_header "Creating Namespace"

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_info "Namespace '$NAMESPACE' already exists"
    else
        kubectl create namespace "$NAMESPACE"
        print_info "Created namespace '$NAMESPACE'"
    fi
}

################################################################################
# Function: show_deployment_progress
# Shows live status updates while Helm deploys
################################################################################
show_deployment_progress() {
    local namespace="$1"
    local app_label="$2"

    echo ""
    print_info "Monitoring deployment progress (this may take several minutes)..."
    echo ""

    local count=0
    while true; do
        ((count++))

        # Show a spinner
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local idx=$((count % ${#spinner[@]}))

        # Get pod status
        local pod_status=$(kubectl get pods -n "$namespace" -l app="$app_label" 2>/dev/null | tail -n +2)

        if [ -n "$pod_status" ]; then
            echo -ne "\r${spinner[$idx]} Checking pod status..."

            # Every 5 iterations, show full status
            if [ $((count % 5)) -eq 0 ]; then
                echo ""
                echo -e "${BLUE}Current pod status:${NC}"
                kubectl get pods -n "$namespace" -l app="$app_label"
                echo ""
            fi
        else
            echo -ne "\r${spinner[$idx]} Waiting for pods to be created..."
        fi

        sleep 2
    done
}

################################################################################
# Function: detect_image_version
# Detect available image version from local registry
################################################################################
detect_image_version() {
    local repo_path="$1"

    # Query registry for available tags
    local tags=$(curl -s "http://${REGISTRY_URL}/v2/${repo_path}/tags/list" 2>/dev/null | jq -r '.tags[]' 2>/dev/null | sort -V | tail -1)

    if [ -n "$tags" ]; then
        echo "$tags"
    else
        echo ""
    fi
}

################################################################################
# Function: deploy_component
# Generic function to deploy any Elastic Stack component
################################################################################
deploy_component() {
    local component_name="$1"
    local chart_dir="$2"
    local repo_path="$3"  # Optional: repository path in registry (e.g., "elasticsearch/elasticsearch", "elastic-agent/elastic-agent")

    print_header "Deploying ${component_name^}"

    # Build helm set overrides for image configuration
    local image_overrides=""
    if [ -n "$repo_path" ]; then
        # Always set repository to ensure nested paths are used
        image_overrides="--set image.repository=${repo_path}"

        # Try to detect version from registry
        local detected_version=$(detect_image_version "$repo_path")
        if [ -n "$detected_version" ]; then
            print_info "Detected version in registry: ${detected_version}"
            image_overrides="${image_overrides} --set image.tag=${detected_version}"
        else
            print_warning "Could not detect version from registry, using default from values.yaml"
        fi
    fi

    # Check if release already exists
    if helm list -n "$NAMESPACE" | grep -q "^${component_name}"; then
        print_warning "Release '$component_name' already exists"
        read -p "Do you want to upgrade it? (y/n): " upgrade
        if [[ "$upgrade" =~ ^[Yy]$ ]]; then
            # Start progress monitor in background
            show_deployment_progress "$NAMESPACE" "$component_name" &
            local progress_pid=$!

            # Run helm upgrade with image overrides
            helm upgrade "$component_name" "$chart_dir" \
                --namespace "$NAMESPACE" \
                $image_overrides \
                --wait \
                --timeout 10m

            # Stop progress monitor
            kill $progress_pid 2>/dev/null || true
            wait $progress_pid 2>/dev/null || true

            echo ""
            print_info "${component_name^} upgraded successfully"
        fi
    else
        # Start progress monitor in background
        show_deployment_progress "$NAMESPACE" "$component_name" &
        local progress_pid=$!

        # Run helm install with image overrides
        helm install "$component_name" "$chart_dir" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            $image_overrides \
            --wait \
            --timeout 10m

        # Stop progress monitor
        kill $progress_pid 2>/dev/null || true
        wait $progress_pid 2>/dev/null || true

        echo ""
        print_info "${component_name^} deployed successfully"
    fi
}

################################################################################
# Function: deploy_elasticsearch
################################################################################
deploy_elasticsearch() {
    deploy_component "elasticsearch" "${COMPONENTS[elasticsearch]}" "elasticsearch/elasticsearch"
}

################################################################################
# Function: deploy_kibana
################################################################################
deploy_kibana() {
    deploy_component "kibana" "${COMPONENTS[kibana]}" "kibana/kibana"
}

################################################################################
# Function: deploy_logstash
################################################################################
deploy_logstash() {
    deploy_component "logstash" "${COMPONENTS[logstash]}" "logstash/logstash"
}

################################################################################
# Function: deploy_fleet_server
################################################################################
deploy_fleet_server() {
    deploy_component "fleet-server" "${COMPONENTS[fleet-server]}" "elastic-agent/elastic-agent"
}

################################################################################
# Function: wait_for_ready
################################################################################
wait_for_ready() {
    local component="$1"
    print_header "Waiting for ${component^} to be Ready"

    print_info "Waiting for ${component} pods to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=ready pod \
        -l app="$component" \
        -n "$NAMESPACE" \
        --timeout=600s || true

    print_info "${component^} pods are ready!"
}

################################################################################
# Function: display_status
################################################################################
display_status() {
    print_header "Deployment Status"

    echo ""
    echo -e "${BLUE}All Pods in namespace ${NAMESPACE}:${NC}"
    kubectl get pods -n "$NAMESPACE"

    echo ""
    echo -e "${BLUE}All Services in namespace ${NAMESPACE}:${NC}"
    kubectl get svc -n "$NAMESPACE"

    echo ""
    echo -e "${BLUE}PersistentVolumeClaims:${NC}"
    kubectl get pvc -n "$NAMESPACE"
}

################################################################################
# Function: display_access_instructions
################################################################################
display_access_instructions() {
    print_header "Access Instructions"

    echo ""
    echo -e "${GREEN}=== Elasticsearch ===${NC}"
    echo ""
    echo "1. Port-forward to your local machine:"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/elasticsearch-master 9200:9200${NC}"
    echo ""
    echo "2. Test the connection:"
    echo -e "   ${YELLOW}curl http://localhost:9200${NC}"
    echo ""
    echo "3. Check cluster health:"
    echo -e "   ${YELLOW}curl http://localhost:9200/_cluster/health?pretty${NC}"
    echo ""

    echo -e "${GREEN}=== Kibana ===${NC}"
    echo ""
    echo "1. Port-forward to access Kibana web UI:"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/kibana 5601:5601${NC}"
    echo ""
    echo "2. Open in your browser:"
    echo -e "   ${YELLOW}http://localhost:5601${NC}"
    echo ""

    echo -e "${GREEN}=== Logstash ===${NC}"
    echo ""
    echo "1. Port-forward to send data via HTTP:"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/logstash 8080:8080${NC}"
    echo ""
    echo "2. Send a test event:"
    echo -e "   ${YELLOW}curl -X POST http://localhost:8080 -H 'Content-Type: application/json' -d '{\"message\":\"test\"}'${NC}"
    echo ""
    echo "3. Check Logstash metrics:"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/logstash 9600:9600${NC}"
    echo -e "   ${YELLOW}curl http://localhost:9600/_node/stats?pretty${NC}"
    echo ""

    echo -e "${GREEN}=== Fleet Server ===${NC}"
    echo ""
    echo "1. Port-forward Fleet Server:"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/fleet-server 8220:8220${NC}"
    echo ""
    echo "2. Check Fleet Server status:"
    echo -e "   ${YELLOW}curl http://localhost:8220/api/status${NC}"
    echo ""
    echo "3. Configure in Kibana:"
    echo "   - Navigate to Fleet settings in Kibana"
    echo "   - Set Fleet Server URL: http://fleet-server:8220"
    echo "   - Generate enrollment tokens for Elastic Agents"
    echo ""
    echo "4. View Fleet Server logs:"
    echo -e "   ${YELLOW}kubectl logs -n ${NAMESPACE} -l app=fleet-server -f${NC}"
    echo ""

    echo -e "${BLUE}=== Remote Access (SSH Tunnel) ===${NC}"
    echo ""
    echo "If accessing from your local machine to a remote server:"
    echo ""
    echo "1. Create SSH tunnel for all services:"
    echo -e "   ${YELLOW}ssh -i your-key.pem -L 9200:localhost:9200 -L 5601:localhost:5601 -L 8080:localhost:8080 user@server${NC}"
    echo ""
    echo "2. On the remote server, run port-forwards:"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/elasticsearch-master 9200:9200 &${NC}"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/kibana 5601:5601 &${NC}"
    echo -e "   ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/logstash 8080:8080 &${NC}"
    echo ""
    echo "3. Access from local browser:"
    echo -e "   Elasticsearch: ${YELLOW}http://localhost:9200${NC}"
    echo -e "   Kibana:        ${YELLOW}http://localhost:5601${NC}"
    echo ""

    echo -e "${BLUE}=== Other Commands ===${NC}"
    echo ""
    echo "View logs:"
    echo "   kubectl logs -n ${NAMESPACE} -l app=elasticsearch -f"
    echo "   kubectl logs -n ${NAMESPACE} -l app=kibana -f"
    echo "   kubectl logs -n ${NAMESPACE} -l app=logstash -f"
    echo ""
    echo "Uninstall components:"
    echo "   helm uninstall elasticsearch -n ${NAMESPACE}"
    echo "   helm uninstall kibana -n ${NAMESPACE}"
    echo "   helm uninstall logstash -n ${NAMESPACE}"
    echo ""
    echo "Uninstall all:"
    echo "   helm uninstall elasticsearch kibana logstash -n ${NAMESPACE}"
    echo ""
}

################################################################################
# Main Execution
################################################################################
main() {
    echo "Elastic Stack Kubernetes Deployment (Air-gapped)"
    echo "Components: Elasticsearch, Kibana, Logstash, Fleet Server"
    echo "Using local registry: ${REGISTRY_URL}"
    echo ""

    check_prerequisites
    create_namespace

    # Deploy Elasticsearch
    echo ""
    read -p "Deploy Elasticsearch? (y/n): " deploy_es
    if [[ "$deploy_es" =~ ^[Yy]$ ]]; then
        deploy_elasticsearch
        wait_for_ready "elasticsearch"
    else
        print_info "Skipping Elasticsearch deployment"
    fi

    # Deploy Kibana
    echo ""
    read -p "Deploy Kibana? (y/n): " deploy_kb
    if [[ "$deploy_kb" =~ ^[Yy]$ ]]; then
        deploy_kibana
        wait_for_ready "kibana"
    else
        print_info "Skipping Kibana deployment"
    fi

    # Deploy Logstash
    echo ""
    read -p "Deploy Logstash? (y/n): " deploy_ls
    if [[ "$deploy_ls" =~ ^[Yy]$ ]]; then
        deploy_logstash
        wait_for_ready "logstash"
    else
        print_info "Skipping Logstash deployment"
    fi

    # Fleet Server requires manual Kibana configuration first
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Fleet Server Setup${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${BLUE}Fleet Server requires manual configuration in Kibana before deployment.${NC}"
    echo ""
    echo "Please follow these steps:"
    echo "  1. Access Kibana UI (see instructions below)"
    echo "  2. Configure Fleet settings in Kibana"
    echo "  3. Create Fleet Server policy"
    echo "  4. Then deploy Fleet Server separately"
    echo ""
    echo "For detailed instructions, see:"
    echo -e "  ${YELLOW}docs/FLEET_SETUP.md${NC}"
    echo ""
    read -p "Do you want to deploy Fleet Server now? (NOT RECOMMENDED - Configure Kibana first) (y/n): " deploy_fleet
    if [[ "$deploy_fleet" =~ ^[Yy]$ ]]; then
        print_warning "Deploying Fleet Server without Kibana configuration may result in startup issues"
        deploy_fleet_server
        wait_for_ready "fleet-server"
    else
        print_info "Skipping Fleet Server deployment - configure Kibana first, then run:"
        echo -e "  ${YELLOW}helm install fleet-server ./fleet-server --namespace elastic${NC}"
    fi

    # Display final status
    display_status
    display_access_instructions

    print_info "Deployment complete!"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Configure Fleet in Kibana (see docs/FLEET_SETUP.md)"
    echo "  2. Deploy Fleet Server after Kibana configuration"
    echo "  3. Enroll Elastic Agents to Fleet Server"
}

# Run main
main
