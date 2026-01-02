#!/bin/bash
################################################################################
# Script: setup-machine.sh
# Purpose: Initial setup for Ubuntu machine (Docker, Git, prerequisites)
# Usage: ./setup-machine.sh
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
# Check if running on Ubuntu/Debian
################################################################################
check_os() {
    print_header "Checking Operating System"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_info "OS: $NAME $VERSION"

        if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
            print_warning "This script is designed for Ubuntu/Debian"
            read -p "Continue anyway? (y/n): " continue_install
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    else
        print_warning "Cannot determine OS type"
    fi
}

################################################################################
# Update system packages
################################################################################
update_packages() {
    print_header "Updating System Packages"

    print_info "Running apt update..."
    sudo apt update

    print_info "Upgrading installed packages..."
    read -p "Do you want to upgrade existing packages? (y/n): " upgrade
    if [[ "$upgrade" =~ ^[Yy]$ ]]; then
        sudo apt upgrade -y
        print_info "✓ Packages upgraded"
    else
        print_info "Skipping package upgrade"
    fi

    print_info "✓ Package lists updated"
}

################################################################################
# Install Docker
################################################################################
install_docker() {
    print_header "Installing Docker"

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        print_info "Docker is already installed: $(docker --version)"
        read -p "Reinstall Docker? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "Skipping Docker installation"
            return 0
        fi
    fi

    print_info "Downloading Docker installation script..."
    curl -fsSL https://get.docker.com -o get-docker.sh

    print_info "Installing Docker..."

    # Try installing Docker with error handling
    if sudo sh get-docker.sh; then
        print_info "Cleaning up installation script..."
        rm get-docker.sh
        print_info "✓ Docker installed: $(docker --version)"
        return 0
    fi

    # Docker installation failed - offer workarounds
    print_error "Docker installation failed!"
    echo ""
    print_warning "This is often caused by temporary issues with Docker's package repository"
    echo ""

    while true; do
        echo "Choose a workaround:"
        echo ""
        echo "  1) Retry installation (wait 30s and try again)"
        echo "     Use if: Temporary repository sync issue"
        echo ""
        echo "  2) Install docker.io from Ubuntu repositories"
        echo "     Use if: You want stable Ubuntu-packaged Docker"
        echo "     Note: May be an older version"
        echo ""
        echo "  3) Manual containerd version selection"
        echo "     Use if: Specific containerd package is missing"
        echo "     Note: Advanced option"
        echo ""
        echo "  4) Skip Docker installation"
        echo ""
        read -p "Select option (1-4): " choice

        case $choice in
            1)
                print_info "Waiting 30 seconds before retry..."
                sleep 30
                print_info "Retrying Docker installation..."
                if sudo sh get-docker.sh; then
                    print_info "Cleaning up installation script..."
                    rm get-docker.sh
                    print_info "✓ Docker installed: $(docker --version)"
                    return 0
                else
                    print_error "Retry failed. Try another option."
                    echo ""
                fi
                ;;
            2)
                print_info "Installing docker.io from Ubuntu repositories..."
                rm get-docker.sh
                sudo apt update
                sudo apt install -y docker.io docker-compose

                if command -v docker &> /dev/null; then
                    print_info "✓ Docker installed: $(docker --version)"
                    return 0
                else
                    print_error "Installation failed. Try another option."
                    echo ""
                fi
                ;;
            3)
                print_info "Checking available containerd.io versions..."
                rm get-docker.sh

                # Update package cache
                sudo apt update

                # Get latest containerd.io version automatically
                echo ""
                print_info "Detecting latest available containerd.io version..."
                latest_containerd=$(apt-cache madison containerd.io | head -1 | awk '{print $3}')

                if [ -n "$latest_containerd" ]; then
                    print_info "Latest version detected: $latest_containerd"
                    echo ""
                    read -p "Install latest version ($latest_containerd)? (y/n): " use_latest

                    if [[ "$use_latest" =~ ^[Yy]$ ]]; then
                        containerd_version="$latest_containerd"
                    else
                        # Show available versions for manual selection
                        echo ""
                        print_info "Available containerd.io versions:"
                        apt-cache madison containerd.io | head -10
                        echo ""

                        read -p "Enter specific version or 'cancel': " containerd_version

                        if [[ "$containerd_version" == "cancel" ]] || [[ -z "$containerd_version" ]]; then
                            print_info "Cancelled. Choose another option."
                            echo ""
                            continue
                        fi
                    fi
                else
                    print_error "Could not detect containerd.io versions"
                    echo ""
                    continue
                fi

                print_info "Installing Docker with containerd.io=$containerd_version..."

                # Install Docker components with specific containerd version
                sudo apt install -y \
                    apt-transport-https \
                    ca-certificates \
                    curl \
                    gnupg \
                    lsb-release

                # Add Docker's GPG key
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

                # Add Docker repository
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                sudo apt update

                # Install with specific containerd version
                if sudo apt install -y containerd.io=$containerd_version docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; then
                    print_info "✓ Docker installed: $(docker --version)"
                    return 0
                else
                    print_error "Installation failed. Try another option."
                    echo ""
                fi
                ;;
            4)
                print_warning "Skipping Docker installation"
                rm get-docker.sh 2>/dev/null || true
                return 1
                ;;
            *)
                print_error "Invalid option. Please choose 1-4."
                echo ""
                ;;
        esac
    done
}

################################################################################
# Configure Docker permissions
################################################################################
configure_docker_permissions() {
    print_header "Configuring Docker Permissions"

    local current_user=$(whoami)
    print_info "Adding user '$current_user' to docker group..."

    sudo usermod -aG docker "$current_user"

    print_info "✓ User added to docker group"
    print_warning "You need to log out and back in for group changes to take effect"
    print_info "Or run: newgrp docker"
}

################################################################################
# Verify Docker installation
################################################################################
verify_docker() {
    print_header "Verifying Docker Installation"

    print_info "Docker version:"
    docker --version || true

    echo ""
    print_info "Testing Docker with newgrp (temporary group activation)..."

    # Use newgrp to test Docker without logout
    if newgrp docker << 'EOFTEST'
docker info > /dev/null 2>&1
EOFTEST
    then
        print_info "✓ Docker is working correctly"
    else
        print_warning "⚠ Docker requires logout/login or run: newgrp docker"
    fi
}

################################################################################
# Configure Git
################################################################################
configure_git() {
    print_header "Configuring Git"

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        print_info "Git not found. Installing git..."
        sudo apt install -y git
        print_info "✓ Git installed: $(git --version)"
    else
        print_info "Git is already installed: $(git --version)"
    fi

    echo ""
    print_info "Git requires your name and email for commits"
    echo ""

    # Check current git config
    local current_name=$(git config --global user.name 2>/dev/null || echo "")
    local current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [ -n "$current_name" ] && [ -n "$current_email" ]; then
        print_info "Current Git configuration:"
        echo "  Name:  $current_name"
        echo "  Email: $current_email"
        echo ""
        read -p "Keep current configuration? (y/n): " keep_config
        if [[ "$keep_config" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing Git configuration"
            return 0
        fi
    fi

    # Interactive Git configuration
    echo ""
    read -p "Enter your Git username: " git_name
    while [ -z "$git_name" ]; do
        print_warning "Username cannot be empty"
        read -p "Enter your Git username: " git_name
    done

    read -p "Enter your Git email: " git_email
    while [ -z "$git_email" ]; do
        print_warning "Email cannot be empty"
        read -p "Enter your Git email: " git_email
    done

    # Set Git configuration
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    print_info "✓ Git configured:"
    echo "  Name:  $(git config --global user.name)"
    echo "  Email: $(git config --global user.email)"

    # Optional: Set default branch name
    echo ""
    read -p "Set default branch name to 'main'? (y/n): " set_main
    if [[ "$set_main" =~ ^[Yy]$ ]]; then
        git config --global init.defaultBranch main
        print_info "✓ Default branch set to 'main'"
    fi
}

################################################################################
# Install additional useful tools
################################################################################
install_additional_tools() {
    print_header "Installing Additional Tools"

    echo ""
    print_info "Recommended tools for air-gapped deployment:"
    echo "  - curl: Download files"
    echo "  - wget: Download files"
    echo "  - jq: JSON processor (used by scripts)"
    echo "  - vim: Text editor"
    echo ""

    read -p "Install recommended tools? (y/n): " install_tools
    if [[ "$install_tools" =~ ^[Yy]$ ]]; then
        print_info "Installing tools..."
        sudo apt install -y curl wget jq vim

        print_info "✓ Additional tools installed"
    else
        print_info "Skipping additional tools"
    fi
}

################################################################################
# Clone additional repository (optional)
################################################################################
clone_repository() {
    print_header "Clone Additional Repository"

    echo ""
    print_info "This script is part of helm-fleet-deployment (already cloned)"
    echo ""
    read -p "Do you want to clone an additional repository? (y/n): " clone_repo
    if [[ ! "$clone_repo" =~ ^[Yy]$ ]]; then
        print_info "Skipping repository clone"
        return 0
    fi

    read -p "Enter repository URL: " repo_url
    if [ -z "$repo_url" ]; then
        print_info "No URL provided, skipping"
        return 0
    fi

    # Extract repo name from URL (last part without .git)
    local default_dir=$(basename "$repo_url" .git)

    read -p "Enter directory name (default: $default_dir): " dir_name
    dir_name=${dir_name:-$default_dir}

    # Clone one level up from current directory
    local clone_path="../$dir_name"

    if [ -d "$clone_path" ]; then
        print_warning "Directory '$clone_path' already exists"
        return 0
    fi

    print_info "Cloning repository to: $clone_path"
    git clone "$repo_url" "$clone_path"

    print_info "✓ Repository cloned to: $clone_path"
}

################################################################################
# Display summary
################################################################################
display_summary() {
    print_header "Setup Complete"

    echo ""
    print_info "Installation Summary:"
    echo ""

    # Docker
    if command -v docker &> /dev/null; then
        echo "  ✓ Docker: $(docker --version)"
    else
        echo "  ✗ Docker: Not installed"
    fi

    # Git
    if command -v git &> /dev/null; then
        echo "  ✓ Git: $(git --version)"
        local git_name=$(git config --global user.name 2>/dev/null || echo "Not configured")
        local git_email=$(git config --global user.email 2>/dev/null || echo "Not configured")
        echo "    Name:  $git_name"
        echo "    Email: $git_email"
    else
        echo "  ✗ Git: Not installed"
    fi

    # Additional tools
    local tools_status=""
    command -v curl &> /dev/null && tools_status+="curl "
    command -v wget &> /dev/null && tools_status+="wget "
    command -v jq &> /dev/null && tools_status+="jq "
    if [ -n "$tools_status" ]; then
        echo "  ✓ Tools: $tools_status"
    fi

    echo ""
    print_warning "IMPORTANT: Docker group membership requires a new login session!"
    echo ""
    print_info "You have two options:"
    echo ""
    echo "  Option 1 (Quick): Activate in current session"
    echo "    Run: newgrp docker"
    echo "    This creates a new shell with docker group active"
    echo ""
    echo "  Option 2 (Permanent): Logout and login"
    echo "    Run: exit"
    echo "    Then SSH/login again"
    echo ""

    read -p "Do you want to activate Docker permissions now with 'newgrp docker'? (y/n): " activate_now
    if [[ "$activate_now" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Starting new shell with docker group..."
        print_info "You can continue using Docker commands in this shell"
        print_info "Type 'exit' to return to the previous shell"
        echo ""
        exec newgrp docker
    else
        echo ""
        print_warning "Remember to run 'newgrp docker' or logout/login before using Docker!"
        echo ""
    fi

    print_info "Next steps (after activating docker group):"
    echo ""
    echo "  1. Test Docker:"
    echo "     docker run hello-world"
    echo ""
    echo "  2. For air-gapped deployment:"
    echo "     cd helm-fleet-deployment/deployment_infrastructure"
    echo "     ./collect-all.sh"
    echo ""
}

################################################################################
# Main execution
################################################################################
main() {
    echo "Ubuntu Machine Setup Script"
    echo "Sets up Docker, Git, and prerequisites"
    echo ""

    check_os
    update_packages
    install_docker
    configure_docker_permissions
    verify_docker
    configure_git
    install_additional_tools
    clone_repository
    display_summary

    print_info "Setup complete!"
}

# Run main
main
