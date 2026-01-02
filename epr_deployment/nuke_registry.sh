#!/bin/bash

################################################################################
# Script: nuke_registry.sh
# Purpose: Complete cleanup of EPR deployment - removes all containers, images, and files
# Usage: ./nuke_registry.sh
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGISTRY_NAME="elastic-registry"
REGISTRY_VOLUME="registry-data"
IMAGES_DIR="./images"
IMAGE_LIST_FILE="image-list.txt"

################################################################################
# Function: print_header
################################################################################
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

################################################################################
# Function: print_info
################################################################################
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

################################################################################
# Function: print_warning
################################################################################
print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

################################################################################
# Function: print_error
################################################################################
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# Function: confirm_nuke
################################################################################
confirm_nuke() {
    print_header "EPR Registry Nuke - Cleanup Tool"

    echo -e "${YELLOW}This will remove:${NC}"
    echo "  - Registry container: $REGISTRY_NAME"
    echo "  - Registry volume: $REGISTRY_VOLUME"
    echo "  - All Elastic Docker images (version 9.2.2)"
    echo "  - All localhost:5000/* tagged images"
    echo "  - Directory: $IMAGES_DIR"
    echo "  - File: $IMAGE_LIST_FILE"
    echo ""

    read -p "Are you sure you want to proceed? (yes/no): " confirmation

    if [[ "$confirmation" != "yes" ]]; then
        print_warning "Cleanup cancelled."
        exit 0
    fi
}

################################################################################
# Function: stop_registry
################################################################################
stop_registry() {
    print_header "Stopping Registry Container"

    if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        print_info "Stopping $REGISTRY_NAME..."
        docker stop "$REGISTRY_NAME" 2>/dev/null && print_info "Container stopped ✓" || print_warning "Container was not running"

        print_info "Removing container..."
        docker rm "$REGISTRY_NAME" 2>/dev/null && print_info "Container removed ✓" || print_warning "Container already removed"
    else
        print_info "No registry container found to remove"
    fi
}

################################################################################
# Function: remove_volume
################################################################################
remove_volume() {
    print_header "Removing Registry Volume"

    if docker volume ls | grep -q "$REGISTRY_VOLUME"; then
        print_info "Removing volume: $REGISTRY_VOLUME"
        docker volume rm "$REGISTRY_VOLUME" 2>/dev/null && print_info "Volume removed ✓" || print_warning "Volume removal failed (may be in use)"
    else
        print_info "No registry volume found"
    fi
}

################################################################################
# Function: remove_images
################################################################################
remove_images() {
    print_header "Removing Docker Images"

    # Remove Elastic images (9.2.2)
    print_info "Removing Elastic images (9.2.2)..."
    local elastic_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'docker.elastic.co.*:9.2.2')

    if [ -n "$elastic_images" ]; then
        echo "$elastic_images" | while read -r image; do
            print_info "Removing: $image"
            docker rmi "$image" 2>/dev/null || print_warning "Failed to remove $image"
        done
        print_info "Elastic images removed ✓"
    else
        print_info "No Elastic 9.2.2 images found"
    fi

    # Remove localhost:5000/* images
    print_info "Removing localhost:5000/* images..."
    local registry_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^localhost:5000/')

    if [ -n "$registry_images" ]; then
        echo "$registry_images" | while read -r image; do
            print_info "Removing: $image"
            docker rmi "$image" 2>/dev/null || print_warning "Failed to remove $image"
        done
        print_info "Registry images removed ✓"
    else
        print_info "No localhost:5000 images found"
    fi

    # Remove registry:2 image (optional)
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q '^registry:2$'; then
        read -p "Remove registry:2 image? (y/n): " remove_registry_img
        if [[ "$remove_registry_img" =~ ^[Yy]$ ]]; then
            docker rmi registry:2 2>/dev/null && print_info "registry:2 removed ✓"
        fi
    fi
}

################################################################################
# Function: remove_files
################################################################################
remove_files() {
    print_header "Removing Files and Directories"

    if [ -d "$IMAGES_DIR" ]; then
        print_info "Removing directory: $IMAGES_DIR"
        rm -rf "$IMAGES_DIR" && print_info "Directory removed ✓"
    else
        print_info "No images directory found"
    fi

    if [ -f "$IMAGE_LIST_FILE" ]; then
        print_info "Removing file: $IMAGE_LIST_FILE"
        rm -f "$IMAGE_LIST_FILE" && print_info "File removed ✓"
    else
        print_info "No image list file found"
    fi
}

################################################################################
# Function: docker_prune
################################################################################
docker_prune() {
    print_header "Docker System Cleanup"

    print_info "Pruning Docker system (removes dangling images, stopped containers, etc.)..."
    docker system prune -f
    print_info "Docker system pruned ✓"
}

################################################################################
# Function: show_summary
################################################################################
show_summary() {
    print_header "Cleanup Summary"

    echo -e "${GREEN}Remaining Docker Resources:${NC}\n"

    # Show containers
    echo -e "${YELLOW}Containers:${NC}"
    local container_count=$(docker ps -a --format '{{.Names}}' | wc -l)
    if [ "$container_count" -eq 0 ]; then
        echo "  No containers"
    else
        docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | head -n 6
    fi
    echo ""

    # Show images
    echo -e "${YELLOW}Images:${NC}"
    local image_count=$(docker images --format '{{.Repository}}' | wc -l)
    if [ "$image_count" -eq 0 ]; then
        echo "  No images"
    else
        docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | head -n 6
    fi
    echo ""

    # Show volumes
    echo -e "${YELLOW}Volumes:${NC}"
    local volume_count=$(docker volume ls --format '{{.Name}}' | wc -l)
    if [ "$volume_count" -eq 0 ]; then
        echo "  No volumes"
    else
        docker volume ls --format 'table {{.Name}}\t{{.Driver}}' | head -n 6
    fi
    echo ""

    # Show disk usage
    echo -e "${YELLOW}Disk Usage:${NC}"
    df -h . | tail -n 1 | awk '{print "  Available: "$4" / "$2" ("$5" used)"}'
    echo ""

    print_info "Cleanup complete! Ready for fresh deployment."
}

################################################################################
# Main Execution
################################################################################
main() {
    confirm_nuke
    stop_registry
    remove_volume
    remove_images
    remove_files
    docker_prune
    show_summary

    print_header "Nuke Complete!"

    echo -e "${GREEN}Next Steps:${NC}"
    echo "1. Pull latest scripts: git pull"
    echo "2. Run: ./collect-images.sh"
    echo "3. Run: ./epr.sh"
}

# Run main function
main
