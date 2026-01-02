#!/bin/bash

################################################################################
# Script: epr.sh (Elastic Private Registry)
# Purpose: Deploy a local container registry and load images for air-gapped use
# Usage: ./epr.sh
################################################################################

# Don't use set -e here as it causes issues with arithmetic operations
# We'll handle errors explicitly in each function instead

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory to find deployment_infrastructure
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Configuration
REGISTRY_NAME="elastic-registry"
REGISTRY_PORT="5000"
REGISTRY_VOLUME="registry-data"
IMAGES_DIR="$REPO_ROOT/deployment_infrastructure/images"
IMAGE_LIST_FILE="$REPO_ROOT/deployment_infrastructure/image-list.txt"
REGISTRY_URL="localhost:${REGISTRY_PORT}"

################################################################################
# Function: print_header
# Purpose: Display a formatted header message
################################################################################
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

################################################################################
# Function: print_info
# Purpose: Display informational message
################################################################################
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

################################################################################
# Function: print_warning
# Purpose: Display warning message
################################################################################
print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

################################################################################
# Function: print_error
# Purpose: Display error message
################################################################################
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# Function: check_dependencies
# Purpose: Verify required tools are installed
################################################################################
check_dependencies() {
    print_header "Checking Dependencies"

    local deps=("docker")
    local missing=()

    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            print_info "$dep is installed "
        else
            print_error "$dep is NOT installed "
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Please install Docker first:"
        echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
        echo "  sudo sh get-docker.sh"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    print_info "All dependencies satisfied!"
}

################################################################################
# Function: check_existing_registry
# Purpose: Check if registry is already running
################################################################################
check_existing_registry() {
    print_header "Checking for Existing Registry"

    if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        print_warning "Registry container '$REGISTRY_NAME' already exists"

        if docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
            print_info "Registry is currently running"

            read -p "Do you want to restart it? (y/n): " restart_choice
            if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
                print_info "Stopping existing registry..."
                docker stop "$REGISTRY_NAME"
                docker rm "$REGISTRY_NAME"
                return 0
            else
                print_info "Using existing registry"
                return 1
            fi
        else
            print_info "Removing stopped registry container..."
            docker rm "$REGISTRY_NAME"
        fi
    fi

    return 0
}

################################################################################
# Function: deploy_registry
# Purpose: Deploy a local Docker registry container
################################################################################
deploy_registry() {
    print_header "Deploying Local Container Registry"

    print_info "Starting registry container: $REGISTRY_NAME"
    print_info "Port: $REGISTRY_PORT"
    print_info "Volume: $REGISTRY_VOLUME"

    # Run the registry container
    docker run -d \
        --name "$REGISTRY_NAME" \
        --restart=always \
        -p "${REGISTRY_PORT}:5000" \
        -v "${REGISTRY_VOLUME}:/var/lib/registry" \
        registry:2

    # Wait for registry to be ready
    print_info "Waiting for registry to be ready..."
    sleep 5

    # Test registry
    if curl -s "http://${REGISTRY_URL}/v2/" > /dev/null; then
        print_info "Registry is up and running! "
        print_info "Access it at: http://${REGISTRY_URL}"
    else
        print_error "Registry health check failed"
        exit 1
    fi
}

################################################################################
# Function: check_images_directory
# Purpose: Verify the images directory exists with tar files
################################################################################
check_images_directory() {
    print_header "Checking for Image Files"

    if [ ! -d "$IMAGES_DIR" ]; then
        print_error "Images directory not found: $IMAGES_DIR"
        print_info "Please run collect-all.sh in deployment_infrastructure/ first"
        exit 1
    fi

    local tar_count=$(find "$IMAGES_DIR" -name "*.tar" 2>/dev/null | wc -l)

    if [ "$tar_count" -eq 0 ]; then
        print_error "No .tar files found in $IMAGES_DIR"
        print_info "Please run: cd ../deployment_infrastructure && ./collect-all.sh"
        exit 1
    fi

    print_info "Found $tar_count image tar file(s) "
}

################################################################################
# Function: load_images
# Purpose: Load tar files into Docker and push to local registry
################################################################################
load_images() {
    print_header "Loading and Pushing Images"

    local tar_files=("$IMAGES_DIR"/*.tar)
    local total=${#tar_files[@]}
    local current=0
    local success=0
    local failed=0

    for tar_file in "${tar_files[@]}"; do
        ((current++))

        if [ ! -f "$tar_file" ]; then
            continue
        fi

        print_info "[$current/$total] Processing: $(basename "$tar_file")"

        # Load the image from tar file and capture output
        print_info "Loading image into Docker..."
        local load_output=$(docker load -i "$tar_file" 2>&1)
        local load_status=$?

        if [ $load_status -eq 0 ]; then
            print_info "Image loaded successfully"

            # Get the image name and tag from the loaded output
            # Docker load outputs: "Loaded image: image:tag"
            local loaded_image=$(echo "$load_output" | grep "Loaded image:" | sed 's/Loaded image: //')

            if [ -z "$loaded_image" ]; then
                print_warning "Could not determine loaded image name"
                print_warning "Output was: $load_output"
                ((failed++))
                continue
            fi

            print_info "Loaded: $loaded_image"

            # Create new tag for local registry
            # Extract image path and tag, preserving nested repository structure
            local image_with_tag=$(echo "$loaded_image" | cut -d':' -f1)
            local image_tag=$(echo "$loaded_image" | cut -d':' -f2)

            # Remove registry domain (everything before and including the first /)
            # This preserves nested paths like "elastic-agent/elastic-agent"
            local image_path=$(echo "$image_with_tag" | sed 's#^[^/]*/##')

            local registry_tag="${REGISTRY_URL}/${image_path}:${image_tag}"

            print_info "Tagging as: $registry_tag"
            docker tag "$loaded_image" "$registry_tag"

            # Push to local registry
            print_info "Pushing to local registry..."
            if docker push "$registry_tag"; then
                print_info "Push successful"
                ((success++))
            else
                print_error "Failed to push $registry_tag"
                ((failed++))
            fi
        else
            print_error "Failed to load $tar_file"
            ((failed++))
        fi

        echo ""
    done

    print_info "Completed: $success successful, $failed failed"
}


################################################################################
# Function: list_registry_images
# Purpose: Display all images in the local registry
################################################################################
list_registry_images() {
    print_header "Registry Contents"

    print_info "Querying registry catalog..."

    local catalog=$(curl -s "http://${REGISTRY_URL}/v2/_catalog")

    if [ $? -eq 0 ]; then
        echo "$catalog" | jq -r '.repositories[]' 2>/dev/null | while read -r repo; do
            print_info "Repository: $repo"

            # Get tags for this repository
            local tags=$(curl -s "http://${REGISTRY_URL}/v2/${repo}/tags/list" | jq -r '.tags[]?' 2>/dev/null)

            if [ -n "$tags" ]; then
                echo "$tags" | while read -r tag; do
                    echo "    ${REGISTRY_URL}/${repo}:${tag}"
                done
            fi
        done
    else
        print_warning "Could not query registry catalog"
        print_info "You can manually check: curl http://${REGISTRY_URL}/v2/_catalog"
    fi
}

################################################################################
# Function: configure_docker_insecure
# Purpose: Automatically configure Docker to use insecure registry
################################################################################
configure_docker_insecure() {
    print_header "Docker Configuration"

    local daemon_json="/etc/docker/daemon.json"

    # Check if already configured
    if [ -f "$daemon_json" ]; then
        if grep -q "\"insecure-registries\"" "$daemon_json" 2>/dev/null; then
            if grep -q "\"${REGISTRY_URL}\"" "$daemon_json" 2>/dev/null; then
                print_info "Docker is already configured for insecure registry ${REGISTRY_URL}"
                return 0
            else
                print_warning "Docker has insecure-registries configured, but not for ${REGISTRY_URL}"
            fi
        fi
    fi

    print_warning "Docker daemon needs to trust the insecure registry: ${REGISTRY_URL}"
    echo ""

    read -p "Do you want to automatically configure Docker? (y/n): " auto_configure

    if [[ "$auto_configure" =~ ^[Yy]$ ]]; then
        print_info "Configuring Docker daemon..."

        # Backup existing config if it exists
        if [ -f "$daemon_json" ]; then
            print_info "Backing up existing daemon.json..."
            sudo cp "$daemon_json" "${daemon_json}.backup.$(date +%s)" || {
                print_error "Failed to backup daemon.json"
                return 1
            }

            # Read existing config and add insecure-registries
            local temp_json=$(mktemp)
            if sudo cat "$daemon_json" | jq ". + {\"insecure-registries\": ([.\"insecure-registries\"[]?, \"${REGISTRY_URL}\"] | unique)}" > "$temp_json" 2>/dev/null; then
                sudo mv "$temp_json" "$daemon_json"
            else
                print_warning "jq not available or JSON parsing failed, creating simple config..."
                echo "{\"insecure-registries\": [\"${REGISTRY_URL}\"]}" | sudo tee "$daemon_json" > /dev/null
            fi
        else
            # Create new config
            print_info "Creating new daemon.json..."
            echo "{\"insecure-registries\": [\"${REGISTRY_URL}\"]}" | sudo tee "$daemon_json" > /dev/null
        fi

        print_info "Restarting Docker daemon..."
        sudo systemctl restart docker || {
            print_error "Failed to restart Docker. Please restart manually:"
            echo "  sudo systemctl restart docker"
            return 1
        }

        # Wait for Docker to be ready
        sleep 3

        if docker info &> /dev/null; then
            print_info "Docker configured and restarted successfully!"
        else
            print_error "Docker may not be ready yet. Waiting a bit longer..."
            sleep 5
        fi
    else
        echo ""
        echo -e "${YELLOW}Manual configuration instructions:${NC}\n"
        echo "1. Edit Docker daemon config:"
        echo "   sudo nano /etc/docker/daemon.json"
        echo ""
        echo "2. Add the following:"
        echo '   {'
        echo '     "insecure-registries": ["'${REGISTRY_URL}'"]'
        echo '   }'
        echo ""
        echo "3. Restart Docker:"
        echo "   sudo systemctl restart docker"
        echo ""

        read -p "Have you completed the manual configuration? (y/n): " configured
        if [[ ! "$configured" =~ ^[Yy]$ ]]; then
            print_warning "Please configure Docker and re-run this script"
            exit 0
        fi
    fi
}

################################################################################
# Function: display_usage_instructions
# Purpose: Show how to use the registry in Helm/Fleet deployments
################################################################################
display_usage_instructions() {
    print_header "Usage Instructions"

    echo -e "${GREEN}Your private registry is ready!${NC}\n"

    echo -e "Registry URL: ${YELLOW}${REGISTRY_URL}${NC}"
    echo ""

    # Get actual images from the registry for dynamic examples
    local catalog=$(curl -s "http://${REGISTRY_URL}/v2/_catalog" 2>/dev/null)
    local example_repo=""
    local example_tag=""

    if [ -n "$catalog" ]; then
        # Get first repository from catalog
        example_repo=$(echo "$catalog" | jq -r '.repositories[0]?' 2>/dev/null)

        if [ -n "$example_repo" ] && [ "$example_repo" != "null" ]; then
            # Get first tag for this repository
            local tags=$(curl -s "http://${REGISTRY_URL}/v2/${example_repo}/tags/list" 2>/dev/null)
            example_tag=$(echo "$tags" | jq -r '.tags[0]?' 2>/dev/null)
        fi
    fi

    # Fallback to generic examples if we couldn't query registry
    if [ -z "$example_repo" ] || [ "$example_repo" == "null" ] || [ -z "$example_tag" ] || [ "$example_tag" == "null" ]; then
        example_repo="elasticsearch"
        example_tag="8.11.0"
    fi

    echo -e "${BLUE}Using with Helm:${NC}"
    echo "Update your values.yaml or use --set flags:"
    echo ""
    echo "  image:"
    echo "    repository: ${REGISTRY_URL}/${example_repo}"
    echo "    tag: ${example_tag}"
    echo ""

    echo -e "${BLUE}Using with Fleet:${NC}"
    echo "Reference images in your Fleet deployment:"
    echo "  ${REGISTRY_URL}/${example_repo}:${example_tag}"
    echo ""

    echo -e "${BLUE}Pulling images:${NC}"
    echo "  docker pull ${REGISTRY_URL}/${example_repo}:${example_tag}"
    echo ""

    echo -e "${BLUE}Managing the registry:${NC}"
    echo "  Stop:    docker stop $REGISTRY_NAME"
    echo "  Start:   docker start $REGISTRY_NAME"
    echo "  Remove:  docker rm -f $REGISTRY_NAME"
    echo "  Logs:    docker logs $REGISTRY_NAME"
    echo ""
}

################################################################################
# Main Execution
################################################################################
main() {
    print_header "Elastic Private Registry (EPR) Deployment"

    # Check if user wants to skip registry deployment
    if [ "$1" == "--load-only" ]; then
        print_info "Load-only mode: Skipping registry deployment"
        check_dependencies
        check_images_directory
        load_images
        list_registry_images
        display_usage_instructions
        exit 0
    fi

    # Full deployment flow
    check_dependencies
    configure_docker_insecure

    # Deploy registry if needed
    if check_existing_registry; then
        deploy_registry
    fi

    # Check for images and load them
    check_images_directory
    load_images
    list_registry_images
    display_usage_instructions

    print_header "Deployment Complete!"
}

# Run main function
main "$@"
