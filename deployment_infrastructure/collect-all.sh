#!/bin/bash

################################################################################
# Script: collect-all.sh
# Purpose: Collect container images AND k3s components for air-gapped deployment
# Usage: ./collect-all.sh
################################################################################

# Don't use set -e here as it can cause issues with interactive input
# We'll handle errors explicitly in each function instead

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_DIR="./images"
K3S_DIR="./k3s-files"
HELM_DIR="./helm-files"
IMAGE_LIST_FILE="image-list.txt"
K3S_VERSION="v1.30.0+k3s1"
HELM_VERSION="v3.16.3"

################################################################################
# Print Functions
################################################################################
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
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
# Change to script directory
################################################################################
change_to_script_directory() {
    # Get the directory where this script is located
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # Change to that directory
    cd "$SCRIPT_DIR" || {
        echo -e "${RED}[ERROR]${NC} Failed to change to script directory: $SCRIPT_DIR"
        exit 1
    }

    print_info "Working directory: $SCRIPT_DIR"
}

################################################################################
# Function: check_prerequisites
################################################################################
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    print_info "Docker: $(docker --version)"

    # Check disk space
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    print_info "Available disk space: ${available_space}GB"

    if [ "$available_space" -lt 20 ]; then
        print_warning "Less than 20GB available. You may run out of space."
        read -p "Continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    print_info "Internet connectivity: OK"
}

################################################################################
# Function: create_directories
################################################################################
create_directories() {
    print_header "Creating Output Directories"

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$K3S_DIR"
    mkdir -p "$HELM_DIR"

    print_info "Created: $OUTPUT_DIR (for container images)"
    print_info "Created: $K3S_DIR (for k3s components)"
    print_info "Created: $HELM_DIR (for Helm binary)"
}

################################################################################
# Function: collect_image_urls
################################################################################
collect_image_urls() {
    print_header "Collecting Container Image URLs"

    # Check if image list already exists
    local existing_count=0
    if [ -f "$IMAGE_LIST_FILE" ] && [ -s "$IMAGE_LIST_FILE" ]; then
        existing_count=$(wc -l < "$IMAGE_LIST_FILE" | tr -d ' ')
        echo ""
        print_info "Found existing image list with $existing_count image(s)"
        echo ""
        echo "Existing images:"
        cat -n "$IMAGE_LIST_FILE"
        echo ""

        read -p "Keep existing images and add more? (y/n): " keep_existing

        if [[ ! "$keep_existing" =~ ^[Yy]$ ]]; then
            print_warning "Starting fresh - clearing existing image list"
            > "$IMAGE_LIST_FILE"
            existing_count=0
        else
            print_info "Keeping existing images, you can add more below"
        fi
    else
        # Create empty file
        > "$IMAGE_LIST_FILE"
    fi

    echo ""
    print_info "Enter container image URLs (one per line)"
    print_info "When finished, just press Enter on an empty line"
    echo ""

    local count=0
    while true; do
        read -p "Image URL [$((existing_count+count+1))]: " image_url || {
            echo ""
            print_warning "Input interrupted. Exiting."
            break
        }

        # Trim whitespace
        image_url=$(echo "$image_url" | xargs)

        # Check if empty
        if [ -z "$image_url" ]; then
            if [ $count -eq 0 ] && [ $existing_count -eq 0 ]; then
                print_warning "No images entered yet. Enter at least one image URL."
                continue
            fi
            echo ""
            print_info "Finished collecting images."
            break
        fi

        # Check for duplicates
        if grep -Fxq "$image_url" "$IMAGE_LIST_FILE"; then
            print_warning "Skipping duplicate: $image_url"
            echo ""
            continue
        fi

        echo "$image_url" >> "$IMAGE_LIST_FILE"
        ((count++))
        print_info "✓ Added: $image_url"
        echo ""
    done

    local total=$((existing_count + count))
    print_info "Total images in list: $total (${existing_count} existing, ${count} new)"
}

################################################################################
# Function: pull_and_save_images
################################################################################
pull_and_save_images() {
    print_header "Pulling and Saving Container Images"

    if [ ! -f "$IMAGE_LIST_FILE" ] || [ ! -s "$IMAGE_LIST_FILE" ]; then
        print_warning "No images to pull. Skipping."
        return 0
    fi

    local total=$(wc -l < "$IMAGE_LIST_FILE")
    local current=0
    local success=0
    local failed=0
    local skipped=0

    while IFS= read -r image_url; do
        ((current++))

        # Skip empty lines
        [ -z "$image_url" ] && continue

        # Generate safe filename
        local filename=$(echo "$image_url" | tr '/:' '_')
        local output_file="$OUTPUT_DIR/${filename}.tar"

        # Check if image already exists
        if [ -f "$output_file" ]; then
            print_info "[$current/$total] Skipping (already exists): $image_url"
            ((skipped++))
            echo ""
            continue
        fi

        print_info "[$current/$total] Pulling: $image_url"

        if docker pull "$image_url"; then
            print_info "[$current/$total] Saving to: $output_file"

            if docker save -o "$output_file" "$image_url"; then
                ((success++))
                print_info "[$current/$total] ✓ Successfully saved"
            else
                ((failed++))
                print_error "[$current/$total] ✗ Failed to save image"
            fi
        else
            ((failed++))
            print_error "[$current/$total] ✗ Failed to pull image"
        fi

        echo ""
    done < "$IMAGE_LIST_FILE"

    print_header "Container Images Summary"
    print_info "Successfully processed: $success"
    if [ $skipped -gt 0 ]; then
        print_info "Skipped (already downloaded): $skipped"
    fi
    if [ $failed -gt 0 ]; then
        print_warning "Failed: $failed"
    fi
}

################################################################################
# Function: download_k3s_components
################################################################################
download_k3s_components() {
    print_header "Downloading k3s Components"

    # Save original directory to return to later
    local ORIGINAL_DIR="$(pwd)"

    # Check if k3s files already exist
    local k3s_exists=false
    local airgap_exists=false

    if [ -f "$K3S_DIR/k3s" ]; then
        k3s_exists=true
    fi

    if [ -f "$K3S_DIR/k3s-airgap-images-amd64.tar.gz" ]; then
        airgap_exists=true
    fi

    if [ "$k3s_exists" = true ] && [ "$airgap_exists" = true ]; then
        echo ""
        print_info "k3s components already downloaded (version ${K3S_VERSION})"
        print_info "  ✓ k3s binary: $(ls -lh "$K3S_DIR/k3s" | awk '{print $5}')"
        print_info "  ✓ k3s airgap images: $(ls -lh "$K3S_DIR/k3s-airgap-images-amd64.tar.gz" | awk '{print $5}')"
        echo ""
        read -p "Re-download k3s components? (y/n): " redownload_k3s

        if [[ ! "$redownload_k3s" =~ ^[Yy]$ ]]; then
            print_info "Using existing k3s components"
            return 0
        fi
    else
        echo ""
        print_info "k3s is a lightweight Kubernetes distribution"
        print_info "These files are needed for air-gapped k3s installation"
        echo ""
        read -p "Download k3s components for version ${K3S_VERSION}? (y/n): " download_k3s

        if [[ ! "$download_k3s" =~ ^[Yy]$ ]]; then
            print_warning "Skipping k3s download"
            return 0
        fi
    fi

    cd "$K3S_DIR" || exit 1

    if [ "$k3s_exists" = false ] || [[ "$redownload_k3s" =~ ^[Yy]$ ]]; then
        print_info "Downloading k3s binary..."
        if wget -q --show-progress \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s" \
            -O k3s; then
            chmod +x k3s
            print_info "✓ k3s binary downloaded"
        else
            print_error "✗ Failed to download k3s binary"
        fi
    else
        print_info "✓ k3s binary already exists"
    fi

    if [ "$airgap_exists" = false ] || [[ "$redownload_k3s" =~ ^[Yy]$ ]]; then
        print_info "Downloading k3s airgap images..."
        if wget -q --show-progress \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar.gz" \
            -O k3s-airgap-images-amd64.tar.gz; then
            print_info "✓ k3s airgap images downloaded"
        else
            print_error "✗ Failed to download k3s airgap images"
        fi
    else
        print_info "✓ k3s airgap images already exist"
    fi

    # Note: We don't download the official k3s install script because
    # install-k3s-airgap.sh handles installation directly
    print_info "Installation scripts available in parent directory (deployment_infrastructure/)"

    # Create installation instructions
    cat > INSTALL-K3S.md <<'EOF'
# k3s Air-gapped Installation Instructions

## Files in this directory:
- `k3s` - The k3s binary
- `k3s-airgap-images-amd64.tar.gz` - Required container images
- `INSTALL-K3S.md` - This file

## Files in parent directory (deployment_infrastructure/):
- `install-k3s-airgap.sh` - **AUTOMATED installation script (RECOMMENDED)**
- `uninstall-k3s-complete.sh` - **Complete uninstall script**

## Quick Installation (Recommended)

Run the automated script from the parent directory:

```bash
cd ..
./install-k3s-airgap.sh
```

This script will:
- Install k3s with airgap images
- Configure kubeconfig with correct permissions
- Set up localhost:5000 registry support
- Verify the installation
- Show you next steps

## Manual Installation Steps:

### 1. Copy k3s binary to system path
```bash
sudo cp k3s /usr/local/bin/k3s
sudo chmod +x /usr/local/bin/k3s
```

### 2. Prepare the airgap images
```bash
sudo mkdir -p /var/lib/rancher/k3s/agent/images/
sudo cp k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/
```

### 3. Install k3s
```bash
chmod +x install-k3s-official.sh
INSTALL_K3S_SKIP_DOWNLOAD=true ./install-k3s-official.sh
```

### 4. Configure kubeconfig
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
```

### 5. Verify installation
```bash
kubectl get nodes
kubectl cluster-info
```

### 6. Configure for local registry
Create `/etc/rancher/k3s/registries.yaml`:
```yaml
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
configs:
  "localhost:5000":
    tls:
      insecure_skip_verify: true
```

Then restart k3s:
```bash
sudo systemctl restart k3s
```

## Uninstall k3s

### Quick Uninstall (Recommended)

For complete removal of k3s and all related components:

```bash
./uninstall-k3s-complete.sh
```

This script will:
- Remove all Helm releases
- Delete all Kubernetes resources
- Uninstall k3s service
- Remove all configuration files
- Remove k3s binaries
- Clean up environment variables
- Remove network interfaces
- Optionally remove kubectl and helm

### Manual Uninstall

```bash
/usr/local/bin/k3s-uninstall.sh
```

Note: Manual uninstall may leave configuration files and environment variables.
EOF

    print_info "✓ Installation instructions created: INSTALL-K3S.md"

    cd "$ORIGINAL_DIR"

    print_header "k3s Components Summary"
    print_info "Downloaded k3s version: ${K3S_VERSION}"
    print_info "Files saved to: $K3S_DIR/"
    print_info "See $K3S_DIR/INSTALL-K3S.md for installation instructions"
}

################################################################################
# Function: get_latest_helm_version
################################################################################
get_latest_helm_version() {
    # Try to get latest version from GitHub API (silent, no output except the version)
    local latest_version=$(curl -s --connect-timeout 10 --max-time 20 https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -n "$latest_version" ] && [ "$latest_version" != "null" ]; then
        echo "$latest_version"
    else
        echo "${HELM_VERSION}"
    fi
}

################################################################################
# Function: get_helm_download_url
# Purpose: Get the actual download URL for a specific Helm version from GitHub
################################################################################
get_helm_download_url() {
    local version="$1"

    # Query GitHub API for this specific release
    local release_url="https://api.github.com/repos/helm/helm/releases/tags/${version}"
    local release_data=$(curl -s --connect-timeout 10 --max-time 20 "$release_url")

    # Extract the browser_download_url for linux-amd64 tarball
    local download_url=$(echo "$release_data" | grep -o '"browser_download_url": *"[^"]*linux-amd64\.tar\.gz"' | grep -o 'https://[^"]*')

    if [ -n "$download_url" ]; then
        echo "$download_url"
        return 0
    else
        # Fallback to standard URL structure
        echo "https://get.helm.sh/helm-${version}-linux-amd64.tar.gz"
        return 1
    fi
}

################################################################################
# Function: download_helm
################################################################################
download_helm() {
    print_header "Downloading Helm"

    # Save original directory to return to later
    local ORIGINAL_DIR="$(pwd)"

    # Check if Helm already exists
    local helm_exists=false
    local existing_version=""

    if [ -f "$HELM_DIR/helm" ]; then
        helm_exists=true
        # Try to get version from existing binary
        if [ -x "$HELM_DIR/helm" ]; then
            existing_version=$("$HELM_DIR/helm" version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        fi
    fi

    if [ "$helm_exists" = true ]; then
        echo ""
        print_info "Helm binary already downloaded"
        if [ -n "$existing_version" ] && [ "$existing_version" != "unknown" ]; then
            print_info "  ✓ Existing version: $existing_version"
            print_info "  ✓ Size: $(ls -lh "$HELM_DIR/helm" | awk '{print $5}')"
        fi
        echo ""
        read -p "Re-download Helm? (y/n): " redownload_helm

        if [[ ! "$redownload_helm" =~ ^[Yy]$ ]]; then
            print_info "Using existing Helm binary"
            return 0
        fi
    else
        echo ""
        print_info "Helm is a package manager for Kubernetes"
        print_info "This is needed to deploy applications to Kubernetes"
        echo ""
        read -p "Download Helm? (y/n): " download_helm_confirm

        if [[ ! "$download_helm_confirm" =~ ^[Yy]$ ]]; then
            print_warning "Skipping Helm download"
            return 0
        fi
    fi

    # Ask if user wants latest version
    echo ""
    read -p "Download latest Helm version? (y/n): " use_latest

    local selected_version=""

    if [[ "$use_latest" =~ ^[Yy]$ ]]; then
        print_info "Fetching latest Helm version from GitHub..."
        selected_version=$(get_latest_helm_version)
        print_info "Latest version: $selected_version"
    else
        echo ""
        print_info "Current default version: ${HELM_VERSION}"
        read -p "Enter Helm version to download (e.g., v3.16.3) or press Enter for default: " custom_version

        if [ -n "$custom_version" ]; then
            # Ensure version starts with 'v'
            if [[ ! "$custom_version" =~ ^v ]]; then
                custom_version="v${custom_version}"
            fi
            selected_version="$custom_version"
        else
            selected_version="${HELM_VERSION}"
        fi
        print_info "Using version: $selected_version"
    fi

    cd "$HELM_DIR" || exit 1

    local helm_tarball="helm-${selected_version}-linux-amd64.tar.gz"

    # Get the actual download URL from GitHub API
    print_info "Finding download URL for Helm ${selected_version}..."
    local helm_url=$(get_helm_download_url "$selected_version")
    local url_from_api=$?

    if [ $url_from_api -eq 0 ]; then
        print_info "Found official download URL from GitHub releases"
    else
        print_info "Using standard download URL (fallback)"
    fi

    # Validate URL exists before downloading
    print_info "Validating availability: $helm_url"
    if ! curl --head --silent --fail --connect-timeout 10 --max-time 20 "$helm_url" > /dev/null; then
        print_error "Helm ${selected_version} not available at: $helm_url"
        print_warning "This version may not be released yet or the binary hasn't been uploaded"
        print_info "Please check: https://github.com/helm/helm/releases/tag/${selected_version}"
        cd "$ORIGINAL_DIR"
        return 1
    fi

    print_info "Downloading Helm ${selected_version}..."
    if wget -q --show-progress "$helm_url" -O "$helm_tarball" 2>&1; then
        print_info "✓ Helm tarball downloaded"

        # Extract the helm binary
        print_info "Extracting Helm binary..."
        # First, check what's in the tarball
        local tarball_contents=$(tar -tzf "$helm_tarball" 2>/dev/null | head -5)

        # Try extraction with the standard path
        if tar -xzf "$helm_tarball" linux-amd64/helm --strip-components=1 2>/dev/null; then
            print_info "✓ Helm binary extracted (linux-amd64 path)"
            chmod +x helm
        # If that fails, try without the path prefix (some versions might package differently)
        elif tar -xzf "$helm_tarball" --strip-components=1 2>/dev/null; then
            print_info "✓ Helm binary extracted (alternative path)"
            chmod +x helm
        else
            print_error "✗ Failed to extract Helm binary"
            print_warning "Tarball structure:"
            echo "$tarball_contents"
            cd "$ORIGINAL_DIR"
            return 1
        fi

        # Verify the binary
        if [ -f "./helm" ]; then
            chmod +x ./helm
            # Get version without terminal corruption - capture to variable first
            local helm_version_output=$(./helm version --short 2>&1 | head -1 | cat)
            local helm_version=$(echo "$helm_version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

            if [ "$helm_version" != "unknown" ]; then
                print_info "✓ Helm binary verified: ${helm_version}"
            else
                print_warning "⚠ Helm binary exists but version could not be determined"
            fi
        else
            print_warning "⚠ Could not find Helm binary after extraction"
        fi

        # Keep the tarball for reference but we only need the binary
        print_info "Binary ready for air-gapped installation"

        # Clean up tarball to save space (optional)
        rm -f "$helm_tarball" 2>/dev/null
        print_info "Cleaned up temporary tarball"
    else
        print_error "✗ Failed to download Helm from: $helm_url"
        print_warning "The download failed (possibly 404 Not Found)"

        # If this was the latest version and it failed, suggest using default
        if [[ "$use_latest" =~ ^[Yy]$ ]]; then
            print_info "The latest version (${selected_version}) may not have binaries available yet"
            read -p "Would you like to try the default stable version (${HELM_VERSION}) instead? (y/n): " use_default

            if [[ "$use_default" =~ ^[Yy]$ ]]; then
                selected_version="${HELM_VERSION}"
                print_info "Retrying with version: $selected_version"

                # Get URL for default version
                helm_url=$(get_helm_download_url "$selected_version")
                helm_tarball="helm-${selected_version}-linux-amd64.tar.gz"

                # Try downloading again
                print_info "Downloading Helm ${selected_version}..."
                if wget -q --show-progress "$helm_url" -O "$helm_tarball" 2>&1; then
                    print_info "✓ Helm tarball downloaded"

                    if tar -xzf "$helm_tarball" linux-amd64/helm --strip-components=1 2>/dev/null; then
                        print_info "✓ Helm binary extracted"
                        chmod +x helm

                        if [ -f "./helm" ]; then
                            local helm_version_output=$(./helm version --short 2>&1 | head -1 | cat)
                            local helm_version=$(echo "$helm_version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

                            if [ "$helm_version" != "unknown" ]; then
                                print_info "✓ Helm binary verified: ${helm_version}"
                            fi
                        fi

                        # Clean up tarball
                        rm -f "$helm_tarball"
                        print_info "Cleaned up temporary tarball"
                    fi
                fi
            else
                cd "$ORIGINAL_DIR"
                return 1
            fi
        else
            cd "$ORIGINAL_DIR"
            return 1
        fi
    fi

    # Create installation instructions
    print_info "Creating installation instructions..."
    {
        echo "# Helm Air-gapped Installation Instructions"
        echo ""
        echo "## Files in this directory:"
        echo "- \`helm\` - The Helm binary (${selected_version})"
        echo "- \`INSTALL-HELM.md\` - This file"
        echo ""
        echo "## Quick Installation"
        echo ""
        echo "The helm_charts/deploy.sh script will automatically install Helm if it's not found."
        echo "You can also install it manually:"
        echo ""
        echo "### Option 1: Let deploy.sh handle it (Recommended)"
        echo "\`\`\`bash"
        echo "cd ../../helm_charts"
        echo "./deploy.sh"
        echo "\`\`\`"
        echo ""
        echo "The deploy.sh script will check for Helm and install it automatically from this directory."
        echo ""
        echo "### Option 2: Manual Installation"
        echo "\`\`\`bash"
        echo "sudo cp helm /usr/local/bin/helm"
        echo "sudo chmod +x /usr/local/bin/helm"
        echo "\`\`\`"
        echo ""
        echo "### Verify installation"
        echo "\`\`\`bash"
        echo "helm version"
        echo "\`\`\`"
        echo ""
        echo "## Uninstall Helm"
        echo ""
        echo "\`\`\`bash"
        echo "sudo rm /usr/local/bin/helm"
        echo "\`\`\`"
        echo ""
        echo "Note: This only removes the binary. Helm deployments (releases) will remain in Kubernetes."
    } > INSTALL-HELM.md

    print_info "✓ Installation instructions created: INSTALL-HELM.md"

    # Return to original directory
    cd "$ORIGINAL_DIR" || {
        print_error "Failed to return to original directory: $ORIGINAL_DIR"
        print_warning "Current directory: $(pwd)"
        return 1
    }

    echo ""
    print_header "Helm Download Summary"
    echo ""
    print_info "Downloaded Helm version: ${selected_version}"
    print_info "Files saved to: $HELM_DIR/"
    print_info "See $HELM_DIR/INSTALL-HELM.md for installation instructions"
}

################################################################################
# Function: display_summary
################################################################################
display_summary() {
    print_header "Collection Complete"

    echo ""
    print_info "Container images saved to: $OUTPUT_DIR/"
    if [ -d "$K3S_DIR" ] && [ "$(ls -A $K3S_DIR 2>/dev/null)" ]; then
        print_info "k3s components saved to: $K3S_DIR/"
    fi
    if [ -d "$HELM_DIR" ] && [ "$(ls -A $HELM_DIR 2>/dev/null)" ]; then
        print_info "Helm binary saved to: $HELM_DIR/"
    fi

    echo ""
    print_info "Transfer these directories to your air-gapped machine:"
    echo "  - $OUTPUT_DIR/"
    if [ -d "$K3S_DIR" ] && [ "$(ls -A $K3S_DIR 2>/dev/null)" ]; then
        echo "  - $K3S_DIR/"
    fi
    if [ -d "$HELM_DIR" ] && [ "$(ls -A $HELM_DIR 2>/dev/null)" ]; then
        echo "  - $HELM_DIR/"
    fi

    echo ""
    print_info "On air-gapped machine:"
    echo ""
    echo "  1. Install k3s (if downloaded):"
    echo "     cd $K3S_DIR && cat INSTALL-K3S.md"
    echo ""
    echo "  2. Deploy local registry with images:"
    echo "     cd epr_deployment && ./epr.sh"
    echo ""
    echo "  3. Deploy Elasticsearch to Kubernetes:"
    echo "     cd helm_charts && ./deploy.sh"
    echo ""

    # Show disk usage
    if [ -d "$OUTPUT_DIR" ]; then
        local images_size=$(du -sh "$OUTPUT_DIR" | cut -f1)
        print_info "Container images total size: $images_size"
    fi

    if [ -d "$K3S_DIR" ] && [ "$(ls -A $K3S_DIR 2>/dev/null)" ]; then
        local k3s_size=$(du -sh "$K3S_DIR" | cut -f1)
        print_info "k3s components total size: $k3s_size"
    fi

    if [ -d "$HELM_DIR" ] && [ "$(ls -A $HELM_DIR 2>/dev/null)" ]; then
        local helm_size=$(du -sh "$HELM_DIR" | cut -f1)
        print_info "Helm binary total size: $helm_size"
    fi
}

################################################################################
# Main Execution
################################################################################
main() {
    echo "Air-gapped Collection Tool"
    echo "Collects container images, k3s components, and Helm"
    echo ""

    # Save the starting directory
    local MAIN_START_DIR="$(pwd)"

    change_to_script_directory
    check_prerequisites
    create_directories
    collect_image_urls
    pull_and_save_images
    download_k3s_components
    download_helm

    # Ensure we're in the right directory before summary
    cd "$MAIN_START_DIR" || print_warning "Could not return to starting directory"

    echo ""
    display_summary

    echo ""
    print_info "Collection complete!"
}

# Run main
main
