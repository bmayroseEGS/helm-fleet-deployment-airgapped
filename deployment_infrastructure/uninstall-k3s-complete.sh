#!/bin/bash
################################################################################
# Script: uninstall-k3s-complete.sh
# Purpose: Complete removal of k3s and all related configurations
# Usage: ./uninstall-k3s-complete.sh
################################################################################

set -e

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
# Confirm uninstall
################################################################################
confirm_uninstall() {
    print_header "k3s Complete Uninstallation"

    echo ""
    print_warning "This will completely remove k3s and all related components:"
    echo "  - k3s service and all running containers"
    echo "  - All Kubernetes resources (pods, services, deployments, etc.)"
    echo "  - k3s configuration files"
    echo "  - Registry configuration"
    echo "  - KUBECONFIG environment variable from ~/.bashrc"
    echo "  - k3s data directories"
    echo ""
    print_error "This action cannot be undone!"
    echo ""

    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
}

################################################################################
# Stop and remove all Helm releases
################################################################################
remove_helm_releases() {
    print_header "Removing Helm Releases"

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        print_info "Helm not installed, skipping helm cleanup"
        return 0
    fi

    # Check if kubectl works
    if ! kubectl get namespaces &> /dev/null 2>&1; then
        print_warning "Cannot connect to cluster, skipping helm cleanup"
        return 0
    fi

    # Get all helm releases across all namespaces
    local releases=$(helm list -A -q 2>/dev/null)

    if [ -z "$releases" ]; then
        print_info "No Helm releases found"
        return 0
    fi

    print_info "Found Helm releases to remove:"
    helm list -A

    echo ""
    read -p "Remove all Helm releases? (y/n): " remove_helm
    if [[ "$remove_helm" =~ ^[Yy]$ ]]; then
        while IFS= read -r release; do
            local namespace=$(helm list -A | grep "^$release" | awk '{print $2}')
            print_info "Uninstalling $release from namespace $namespace..."
            helm uninstall "$release" -n "$namespace" || true
        done <<< "$releases"
        print_info "✓ All Helm releases removed"
    else
        print_warning "Skipping Helm release removal"
    fi
}

################################################################################
# Remove Kubernetes resources
################################################################################
remove_kubernetes_resources() {
    print_header "Removing Kubernetes Resources"

    # Check if kubectl works
    if ! kubectl get namespaces &> /dev/null 2>&1; then
        print_warning "Cannot connect to cluster, skipping Kubernetes cleanup"
        return 0
    fi

    # List non-system namespaces
    local namespaces=$(kubectl get namespaces -o custom-columns=:metadata.name --no-headers | grep -v -E "^(default|kube-system|kube-public|kube-node-lease)$")

    if [ -n "$namespaces" ]; then
        print_info "Found custom namespaces:"
        echo "$namespaces"
        echo ""
        read -p "Delete these namespaces and all their resources? (y/n): " delete_ns
        if [[ "$delete_ns" =~ ^[Yy]$ ]]; then
            while IFS= read -r ns; do
                print_info "Deleting namespace: $ns"
                kubectl delete namespace "$ns" --timeout=60s || true
            done <<< "$namespaces"
            print_info "✓ Custom namespaces removed"
        else
            print_warning "Skipping namespace deletion"
        fi
    else
        print_info "No custom namespaces found"
    fi
}

################################################################################
# Uninstall k3s
################################################################################
uninstall_k3s() {
    print_header "Uninstalling k3s"

    # Check if k3s-uninstall.sh exists
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        print_info "Running k3s uninstall script..."
        sudo /usr/local/bin/k3s-uninstall.sh
        print_info "✓ k3s uninstalled"
    elif command -v k3s &> /dev/null; then
        print_warning "k3s is installed but uninstall script not found"
        print_info "Attempting manual cleanup..."

        # Stop k3s service
        if systemctl is-active --quiet k3s; then
            print_info "Stopping k3s service..."
            sudo systemctl stop k3s || true
        fi

        # Disable k3s service
        if systemctl is-enabled --quiet k3s 2>/dev/null; then
            print_info "Disabling k3s service..."
            sudo systemctl disable k3s || true
        fi

        print_info "✓ k3s service stopped"
    else
        print_info "k3s not installed, skipping"
    fi
}

################################################################################
# Remove k3s configuration files
################################################################################
remove_k3s_config() {
    print_header "Removing k3s Configuration Files"

    local files_to_remove=(
        "/etc/rancher/k3s/k3s.yaml"
        "/etc/rancher/k3s/registries.yaml"
        "/etc/systemd/system/k3s.service"
        "/etc/systemd/system/k3s.service.env"
        "/etc/systemd/system/multi-user.target.wants/k3s.service"
    )

    local dirs_to_remove=(
        "/etc/rancher/k3s"
        "/etc/rancher"
        "/var/lib/rancher/k3s"
        "/var/lib/rancher"
    )

    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            print_info "Removing: $file"
            sudo rm -f "$file"
        fi
    done

    for dir in "${dirs_to_remove[@]}"; do
        if [ -d "$dir" ]; then
            print_info "Removing: $dir"
            sudo rm -rf "$dir"
        fi
    done

    # Reload systemd
    print_info "Reloading systemd..."
    sudo systemctl daemon-reload

    print_info "✓ k3s configuration files removed"
}

################################################################################
# Remove k3s binaries
################################################################################
remove_k3s_binaries() {
    print_header "Removing k3s Binaries"

    local binaries=(
        "/usr/local/bin/k3s"
        "/usr/local/bin/kubectl"
        "/usr/local/bin/crictl"
        "/usr/local/bin/ctr"
        "/usr/local/bin/k3s-killall.sh"
        "/usr/local/bin/k3s-uninstall.sh"
    )

    for binary in "${binaries[@]}"; do
        if [ -f "$binary" ]; then
            print_info "Removing: $binary"
            sudo rm -f "$binary"
        fi
    done

    print_info "✓ k3s binaries removed"
}

################################################################################
# Clean up environment variables
################################################################################
cleanup_environment() {
    print_header "Cleaning Environment Variables"

    # Remove KUBECONFIG from .bashrc
    if grep -q "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ~/.bashrc 2>/dev/null; then
        print_info "Removing KUBECONFIG from ~/.bashrc..."
        sed -i '/KUBECONFIG=\/etc\/rancher\/k3s\/k3s.yaml/d' ~/.bashrc
        print_info "✓ KUBECONFIG removed from ~/.bashrc"
    else
        print_info "KUBECONFIG not found in ~/.bashrc"
    fi

    # Unset current session
    unset KUBECONFIG
    print_info "✓ KUBECONFIG unset for current session"
}

################################################################################
# Clean up network interfaces and iptables
################################################################################
cleanup_network() {
    print_header "Cleaning Network Configuration"

    # Remove CNI network interfaces
    print_info "Removing CNI network interfaces..."
    sudo ip link delete cni0 2>/dev/null || true
    sudo ip link delete flannel.1 2>/dev/null || true

    # Clean up iptables rules (optional)
    echo ""
    read -p "Flush iptables rules created by k3s? (y/n): " flush_iptables
    if [[ "$flush_iptables" =~ ^[Yy]$ ]]; then
        print_warning "Flushing iptables rules..."
        sudo iptables -F
        sudo iptables -t nat -F
        sudo iptables -t mangle -F
        sudo iptables -X
        print_info "✓ iptables rules flushed"
    else
        print_info "Skipping iptables cleanup"
    fi

    print_info "✓ Network cleanup complete"
}

################################################################################
# Remove kubectl and helm (optional)
################################################################################
remove_optional_tools() {
    print_header "Optional Tools Cleanup"

    echo ""
    print_info "The following tools were installed by setup-k8s.sh:"
    echo "  - kubectl"
    echo "  - helm"
    echo ""
    read -p "Remove kubectl and helm? (y/n): " remove_tools

    if [[ "$remove_tools" =~ ^[Yy]$ ]]; then
        # Remove kubectl
        if [ -f /usr/local/bin/kubectl ] && ! command -v k3s &> /dev/null; then
            print_info "Removing kubectl..."
            sudo rm -f /usr/local/bin/kubectl
            print_info "✓ kubectl removed"
        fi

        # Remove helm
        if command -v helm &> /dev/null; then
            print_info "Removing helm..."
            sudo rm -f /usr/local/bin/helm
            print_info "✓ helm removed"
        fi
    else
        print_info "Keeping kubectl and helm"
    fi
}

################################################################################
# Verify cleanup
################################################################################
verify_cleanup() {
    print_header "Verifying Cleanup"

    local issues=0

    # Check if k3s is still running
    if systemctl is-active --quiet k3s 2>/dev/null; then
        print_error "✗ k3s service is still running"
        ((issues++))
    else
        print_info "✓ k3s service is not running"
    fi

    # Check if k3s binary exists
    if command -v k3s &> /dev/null; then
        print_warning "⚠ k3s binary still exists"
        ((issues++))
    else
        print_info "✓ k3s binary removed"
    fi

    # Check if config directory exists
    if [ -d /etc/rancher/k3s ]; then
        print_warning "⚠ k3s config directory still exists"
        ((issues++))
    else
        print_info "✓ k3s config directory removed"
    fi

    # Check if data directory exists
    if [ -d /var/lib/rancher/k3s ]; then
        print_warning "⚠ k3s data directory still exists"
        ((issues++))
    else
        print_info "✓ k3s data directory removed"
    fi

    # Check bashrc
    if grep -q "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ~/.bashrc 2>/dev/null; then
        print_warning "⚠ KUBECONFIG still in ~/.bashrc"
        ((issues++))
    else
        print_info "✓ KUBECONFIG removed from ~/.bashrc"
    fi

    echo ""
    if [ $issues -eq 0 ]; then
        print_info "All checks passed! Cleanup complete."
    else
        print_warning "Cleanup completed with $issues issue(s)"
        print_info "You may need to manually remove remaining items"
    fi
}

################################################################################
# Display summary
################################################################################
display_summary() {
    print_header "Uninstall Complete"

    echo ""
    print_info "k3s has been completely removed from your system"
    echo ""
    echo -e "${BLUE}What was removed:${NC}"
    echo "  ✓ k3s service and all containers"
    echo "  ✓ All Kubernetes resources"
    echo "  ✓ k3s configuration files"
    echo "  ✓ k3s data directories"
    echo "  ✓ KUBECONFIG environment variable"
    echo "  ✓ Network interfaces (cni0, flannel.1)"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Reload your shell or run: source ~/.bashrc"
    echo "  2. If you plan to reinstall k3s:"
    echo "     cd k3s-files && ./install-k3s-airgap.sh"
    echo ""
    print_info "Your container images and k3s-files directory are still intact"
    echo ""
}

################################################################################
# Main execution
################################################################################
main() {
    confirm_uninstall
    remove_helm_releases
    remove_kubernetes_resources
    uninstall_k3s
    remove_k3s_config
    remove_k3s_binaries
    cleanup_environment
    cleanup_network
    remove_optional_tools
    verify_cleanup
    display_summary

    print_info "Uninstall complete!"
}

# Run main
main
