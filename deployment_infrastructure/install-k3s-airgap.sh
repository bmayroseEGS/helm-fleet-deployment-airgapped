#!/bin/bash
################################################################################
# Script: install-k3s-airgap.sh
# Purpose: Install k3s in air-gapped mode with local registry configuration
# Usage: Run from deployment_infrastructure directory: ./install-k3s-airgap.sh
################################################################################

set -e

# Get script directory to find k3s-files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K3S_FILES_DIR="$SCRIPT_DIR/k3s-files"

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

################################################################################
# Check prerequisites
################################################################################
check_prerequisites() {
    print_header "Checking Prerequisites"

    print_info "Script directory: $SCRIPT_DIR"
    print_info "Looking for k3s files in: $K3S_FILES_DIR"

    # Check if k3s-files directory exists
    if [ ! -d "$K3S_FILES_DIR" ]; then
        print_error "k3s-files directory not found: $K3S_FILES_DIR"
        print_info "Please run collect-all.sh first to download k3s files"
        exit 1
    fi

    # Check if required files exist in k3s-files subdirectory
    if [ ! -f "$K3S_FILES_DIR/k3s" ] || [ ! -f "$K3S_FILES_DIR/k3s-airgap-images-amd64.tar.gz" ]; then
        print_error "Required files not found in k3s-files directory"
        echo ""
        echo "Expected files in $K3S_FILES_DIR/:"
        echo "  - k3s"
        echo "  - k3s-airgap-images-amd64.tar.gz"
        exit 1
    fi

    print_info "✓ All required files found in k3s-files/"

    # Check if k3s is already installed
    if systemctl is-active --quiet k3s; then
        print_warning "k3s is already running"
        read -p "Do you want to uninstall and reinstall? (y/n): " reinstall
        if [[ "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "Uninstalling existing k3s..."
            sudo /usr/local/bin/k3s-uninstall.sh || true
            sleep 2
        else
            print_info "Skipping installation, will configure registry only"
            SKIP_INSTALL=true
        fi
    fi
}

################################################################################
# Install k3s
################################################################################
install_k3s() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "Skipping k3s installation"
        return 0
    fi

    print_header "Installing k3s"

    # Step 1: Prepare airgap images
    print_info "Step 1/4: Preparing airgap images..."
    sudo mkdir -p /var/lib/rancher/k3s/agent/images/
    sudo cp "$K3S_FILES_DIR/k3s-airgap-images-amd64.tar.gz" /var/lib/rancher/k3s/agent/images/
    print_info "✓ Airgap images copied"

    # Step 2: Copy k3s binary and create symlinks
    print_info "Step 2/4: Installing k3s binary..."
    sudo cp "$K3S_FILES_DIR/k3s" /usr/local/bin/k3s
    sudo chmod +x /usr/local/bin/k3s

    # Create kubectl, crictl, and ctr symlinks
    sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
    sudo ln -sf /usr/local/bin/k3s /usr/local/bin/crictl
    sudo ln -sf /usr/local/bin/k3s /usr/local/bin/ctr

    print_info "✓ k3s binary installed to /usr/local/bin/k3s"
    print_info "✓ kubectl, crictl, ctr symlinks created"

    # Step 3: Create systemd service
    print_info "Step 3/4: Creating k3s systemd service..."

    sudo tee /etc/systemd/system/k3s.service > /dev/null <<'SYSTEMD_EOF'
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/k3s
EnvironmentFile=-/etc/sysconfig/k3s
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=/bin/sh -xc '! /usr/bin/systemctl is-enabled --quiet nm-cloud-setup.service'
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s server

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

    sudo systemctl daemon-reload
    sudo systemctl enable k3s
    sudo systemctl start k3s
    print_info "✓ k3s service created and started"

    # Create uninstall script
    sudo tee /usr/local/bin/k3s-uninstall.sh > /dev/null <<'UNINSTALL_EOF'
#!/bin/sh
set -x
systemctl stop k3s
systemctl disable k3s
rm -f /etc/systemd/system/k3s.service
systemctl daemon-reload
rm -f /usr/local/bin/k3s
rm -f /usr/local/bin/kubectl
rm -f /usr/local/bin/crictl
rm -f /usr/local/bin/ctr
rm -rf /etc/rancher/k3s
rm -rf /var/lib/rancher/k3s
rm -f /usr/local/bin/k3s-uninstall.sh
UNINSTALL_EOF
    sudo chmod +x /usr/local/bin/k3s-uninstall.sh

    # Step 4: Wait for k3s to be ready
    print_info "Step 4/4: Waiting for k3s to be ready..."
    sleep 5

    print_info "✓ k3s installation complete"
}

################################################################################
# Configure kubeconfig
################################################################################
configure_kubeconfig() {
    print_header "Configuring kubeconfig"

    # Set permissions on kubeconfig
    print_info "Setting permissions on kubeconfig file..."
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml

    # Configure KUBECONFIG environment variable
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    # Add to bashrc if not already there
    if ! grep -q "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ~/.bashrc; then
        echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
        print_info "✓ Added KUBECONFIG to ~/.bashrc"
    else
        print_info "✓ KUBECONFIG already in ~/.bashrc"
    fi

    print_info "✓ kubeconfig configured"
}

################################################################################
# Configure local registry
################################################################################
configure_registry() {
    print_header "Configuring Local Registry Support"

    print_info "Creating registry configuration for localhost:5000..."

    sudo mkdir -p /etc/rancher/k3s

    cat <<EOF | sudo tee /etc/rancher/k3s/registries.yaml > /dev/null
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
configs:
  "localhost:5000":
    tls:
      insecure_skip_verify: true
EOF

    print_info "✓ Registry configuration created"

    # Restart k3s to apply changes
    print_info "Restarting k3s to apply registry configuration..."
    sudo systemctl restart k3s

    print_info "Waiting for k3s to restart..."
    sleep 10

    # Fix permissions again after restart
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml

    print_info "✓ k3s restarted with registry configuration"
}

################################################################################
# Verify installation
################################################################################
verify_installation() {
    print_header "Verifying Installation"

    # Ensure KUBECONFIG is set
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    print_info "Checking k3s service status..."
    if systemctl is-active --quiet k3s; then
        print_info "✓ k3s service is running"
    else
        print_error "✗ k3s service is not running"
        print_info "Check status: sudo systemctl status k3s"
        return 1
    fi

    print_info "Checking cluster nodes..."
    if kubectl get nodes &> /dev/null; then
        echo ""
        kubectl get nodes
        echo ""
        print_info "✓ Cluster is accessible"
    else
        print_error "✗ Cannot access cluster"
        return 1
    fi

    print_info "Checking cluster health..."
    kubectl cluster-info

    print_info "Checking registry configuration..."
    if [ -f /etc/rancher/k3s/registries.yaml ]; then
        print_info "✓ Registry configuration exists"
        echo ""
        echo "Registry config:"
        sudo cat /etc/rancher/k3s/registries.yaml
    else
        print_warning "⚠ Registry configuration not found"
    fi
}

################################################################################
# Display next steps
################################################################################
display_next_steps() {
    print_header "Installation Complete"

    echo ""
    echo -e "${GREEN}k3s is now installed and configured!${NC}"
    echo ""
    echo -e "${BLUE}Important:${NC} Reload your shell or run:"
    echo -e "  ${YELLOW}source ~/.bashrc${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "1. Deploy local registry with your images:"
    echo -e "   ${YELLOW}cd ../epr_deployment${NC}"
    echo -e "   ${YELLOW}./epr.sh${NC}"
    echo ""
    echo "2. Deploy Elasticsearch to Kubernetes:"
    echo -e "   ${YELLOW}cd ../helm_charts${NC}"
    echo -e "   ${YELLOW}./deploy.sh${NC}"
    echo ""
    echo -e "${BLUE}Useful commands:${NC}"
    echo "  kubectl get nodes              # Check cluster nodes"
    echo "  kubectl get pods -A            # Check all pods"
    echo "  kubectl get namespaces         # List namespaces"
    echo "  sudo systemctl status k3s      # Check k3s status"
    echo "  sudo systemctl restart k3s     # Restart k3s"
    echo ""
    echo -e "${BLUE}To uninstall k3s:${NC}"
    echo "  /usr/local/bin/k3s-uninstall.sh"
    echo ""
}

################################################################################
# Main execution
################################################################################
main() {
    echo "k3s Air-gapped Installation"
    echo "This script will install k3s with local registry support"
    echo ""

    check_prerequisites
    install_k3s
    configure_kubeconfig
    configure_registry
    verify_installation
    display_next_steps

    print_info "Installation complete!"
}

# Run main
main
