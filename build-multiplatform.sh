#!/bin/bash
set -e

# Multi-platform Docker Build Script
# Builds PyTorch development container for both AMD64 and ARM64 architectures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "${SCRIPT_DIR}/config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    echo "Multi-platform Docker Build Script"
    echo
    echo "USAGE:"
    echo "  $0 [OPTIONS] [COMMAND]"
    echo
    echo "COMMANDS:"
    echo "  build         Build multi-platform image (default)"
    echo "  push          Build and push multi-platform image"
    echo "  build-local   Build for local platform only"
    echo "  inspect       Inspect built image platforms"
    echo "  setup         Setup buildx builder"
    echo "  cleanup       Remove buildx builder"
    echo
    echo "OPTIONS:"
    echo "  --platforms PLATFORMS    Comma-separated list of platforms"
    echo "                          (default: linux/amd64,linux/arm64)"
    echo "  --image IMAGE           Override image name from config"
    echo "  --no-cache              Build without cache"
    echo "  --progress TYPE         Progress output type (auto, plain, tty)"
    echo "  -h, --help             Show this help"
    echo
    echo "EXAMPLES:"
    echo "  $0                                    # Build multi-platform"
    echo "  $0 push                              # Build and push"
    echo "  $0 --platforms linux/amd64 build    # Build AMD64 only"
    echo "  $0 build-local                      # Build for current platform"
    echo
    echo "Current configuration:"
    echo "  Image: ${FULL_IMAGE}"
    echo "  Registry: ${REGISTRY}"
    echo "  Org: ${ORG}"
}

check_buildx() {
    log_info "Checking Docker buildx availability..."

    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx is not available"
        echo "Install Docker Desktop or enable buildx in Docker CLI"
        echo "See: https://docs.docker.com/buildx/working-with-buildx/"
        exit 1
    fi

    log_success "Docker buildx is available"
}

setup_builder() {
    log_info "Setting up buildx builder..."

    local builder_name="multiplatform-builder"

    if docker buildx ls | grep -q "$builder_name"; then
        log_info "Builder '$builder_name' already exists"
        docker buildx use "$builder_name"
    else
        log_info "Creating new builder '$builder_name'..."
        docker buildx create --name "$builder_name" --driver docker-container --use
        docker buildx bootstrap
        log_success "Builder '$builder_name' created and activated"
    fi
}

build_multiplatform() {
    local platforms="$1"
    local push_flag="$2"
    local no_cache_flag="$3"
    local progress_type="$4"

    log_info "Building multi-platform image..."
    log_info "Image: ${FULL_IMAGE}"
    log_info "Platforms: ${platforms}"

    cd "${SCRIPT_DIR}/docker"

    local build_args=(
        "buildx" "build"
        "--platform" "$platforms"
        "-t" "$FULL_IMAGE"
    )

    if [[ "$push_flag" == "true" ]]; then
        build_args+=("--push")
        log_info "Will push to registry after build"
    else
        # For multi-platform without push, we can only inspect
        build_args+=("--load")
        log_warning "Multi-platform images cannot be loaded locally"
        log_warning "Use 'push' command to push to registry, or 'build-local' for local testing"
    fi

    if [[ "$no_cache_flag" == "true" ]]; then
        build_args+=("--no-cache")
        log_info "Building without cache"
    fi

    if [[ -n "$progress_type" ]]; then
        build_args+=("--progress" "$progress_type")
    fi

    build_args+=(".")

    log_info "Running: docker ${build_args[*]}"
    docker "${build_args[@]}"

    if [[ "$push_flag" == "true" ]]; then
        log_success "Multi-platform image built and pushed successfully"
    else
        log_success "Multi-platform image built successfully"
        log_info "Use 'docker buildx imagetools inspect $FULL_IMAGE' to verify platforms"
    fi
}

build_local() {
    local no_cache_flag="$1"

    log_info "Building for local platform..."
    log_info "Image: ${FULL_IMAGE}"
    log_info "Local platform: $(docker version --format '{{.Server.Arch}}')"

    cd "${SCRIPT_DIR}/docker"

    local build_args=("build" "-t" "$FULL_IMAGE")

    if [[ "$no_cache_flag" == "true" ]]; then
        build_args+=("--no-cache")
    fi

    build_args+=(".")

    docker "${build_args[@]}"

    log_success "Local platform image built successfully"
    log_info "Image is available locally as: $FULL_IMAGE"
}

inspect_image() {
    log_info "Inspecting image platforms..."

    if docker buildx imagetools inspect "$FULL_IMAGE" 2>/dev/null; then
        log_success "Image inspection completed"
    else
        log_warning "Could not inspect image. It may not exist in registry yet."
        log_info "Local images:"
        docker images "$FULL_IMAGE" || log_info "No local images found"
    fi
}

cleanup_builder() {
    log_info "Cleaning up buildx builder..."

    local builder_name="multiplatform-builder"

    if docker buildx ls | grep -q "$builder_name"; then
        docker buildx rm "$builder_name"
        log_success "Builder '$builder_name' removed"
    else
        log_info "Builder '$builder_name' not found"
    fi
}

main() {
    local platforms="linux/amd64,linux/arm64"
    local command="build"
    local push_flag="false"
    local no_cache_flag="false"
    local progress_type=""
    local custom_image=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platforms)
                platforms="$2"
                shift 2
                ;;
            --image)
                custom_image="$2"
                shift 2
                ;;
            --no-cache)
                no_cache_flag="true"
                shift
                ;;
            --progress)
                progress_type="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            build|push|build-local|inspect|setup|cleanup)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Override image if specified
    if [[ -n "$custom_image" ]]; then
        FULL_IMAGE="$custom_image"
    fi

    # Execute command
    case $command in
        build)
            check_buildx
            setup_builder
            build_multiplatform "$platforms" "$push_flag" "$no_cache_flag" "$progress_type"
            ;;
        push)
            check_buildx
            setup_builder
            build_multiplatform "$platforms" "true" "$no_cache_flag" "$progress_type"
            ;;
        build-local)
            build_local "$no_cache_flag"
            ;;
        inspect)
            inspect_image
            ;;
        setup)
            check_buildx
            setup_builder
            ;;
        cleanup)
            cleanup_builder
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
