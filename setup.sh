#!/bin/bash
set -e

# DevPod K8s ML Setup Script
# This script sets up SSH keys and deploys the ML development environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "${SCRIPT_DIR}/config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl cannot connect to cluster"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed or not in PATH"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Setup SSH keys
setup_ssh_keys() {
    log_info "Setting up SSH keys..."

    # Check if SSH key exists
    if [[ ! -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
        log_warning "SSH key not found at ${HOME}/.ssh/id_ed25519.pub"
        read -p "Generate new SSH key? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ssh-keygen -t ed25519 -C "devpod-k8s-ml" -f "${HOME}/.ssh/id_ed25519"
        else
            log_error "SSH key required for setup"
            exit 1
        fi
    fi

    # Create or update the SSH key secret
    log_info "Creating SSH key secret in Kubernetes..."

    # Delete existing secret if it exists
    kubectl delete secret ${SSH_KEY_SECRET} -n ${NAMESPACE} 2>/dev/null || true

    # Create new secret
    kubectl create secret generic ${SSH_KEY_SECRET} \
        --from-file=authorized_keys="${HOME}/.ssh/id_ed25519.pub" \
        -n ${NAMESPACE}

    log_success "SSH key secret created"
}

# Build and push Docker image
build_image() {
    log_info "Building Docker image..."

    # Use image from config or ask for custom
    read -p "Use configured image (${FULL_IMAGE})? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        image_name="${FULL_IMAGE}"
    else
        read -p "Enter Docker registry/image name: " image_name
    fi

    # Detect if we need multi-platform build
    local current_arch=$(uname -m)
    local build_strategy=""

    if [[ "$current_arch" == "arm64" ]] || [[ "$current_arch" == "aarch64" ]]; then
        log_info "Detected ARM64 host - likely targeting x86_64 GPU nodes"
        echo "Build options:"
        echo "1) Multi-platform build (linux/amd64,linux/arm64) - recommended"
        echo "2) Single platform (linux/amd64) - for x86_64 GPU nodes only"
        echo "3) Local platform only - for testing"
        read -p "Select option (1-3, default: 1): " -n 1 -r
        echo

        case ${REPLY:-1} in
            1) build_strategy="multi" ;;
            2) build_strategy="amd64" ;;
            3) build_strategy="local" ;;
            *) build_strategy="multi" ;;
        esac
    else
        log_info "Detected x86_64 host - building for GPU nodes"
        build_strategy="amd64"
    fi

    cd "${SCRIPT_DIR}/docker"

    case $build_strategy in
        "multi")
            log_info "Building multi-platform image (amd64 + arm64)..."
            if ! docker buildx version &> /dev/null; then
                log_error "Docker buildx not available. Install Docker Desktop or enable buildx."
                exit 1
            fi

            # Create builder if needed
            docker buildx create --name multiplatform --use 2>/dev/null || docker buildx use multiplatform

            # Ask if user wants to push (required for multi-platform)
            read -p "Push image to registry? (required for multi-platform) (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker buildx build --platform linux/amd64,linux/arm64 --push -t ${image_name} .
                log_success "Multi-platform image built and pushed"
            else
                log_warning "Multi-platform builds require pushing to registry"
                docker buildx build --platform linux/amd64,linux/arm64 --load -t ${image_name} . || {
                    log_warning "Load failed (expected for multi-platform). Building single platform instead..."
                    docker build --platform linux/amd64 -t ${image_name} .
                }
            fi
            ;;
        "amd64")
            log_info "Building single platform image (linux/amd64)..."
            docker build --platform linux/amd64 -t ${image_name} .

            # Ask if user wants to push
            read -p "Push image to registry? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker push ${image_name}
                log_success "Image pushed to registry"
            else
                log_warning "Image not pushed. Make sure image is available to your cluster."
            fi
            ;;
        "local")
            log_info "Building for local platform..."
            docker build -t ${image_name} .
            log_warning "Built for local platform only - may not work on different cluster architecture"
            ;;
    esac

    log_success "Docker image ready: ${image_name}"
}

# Generate manifests from config
generate_manifests() {
    log_info "Generating manifests from config.env..."
    "${SCRIPT_DIR}/generate-manifests.sh" --all
}

# Deploy Kubernetes resources
deploy_k8s() {
    log_info "Deploying Kubernetes resources..."

    # Generate fresh manifests
    generate_manifests

    # Apply storage
    log_info "Creating storage..."
    kubectl apply -f ${SCRIPT_DIR}/k8s/01-storage.yaml

    # Wait for PVCs to be bound using jsonpath
    log_info "Waiting for PVCs to be bound..."
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/ml-workspace -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/ml-datasets -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/ml-outputs -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/ml-cache -n ${NAMESPACE} --timeout=300s

    # Deploy dev pod
    log_info "Deploying development pod..."
    kubectl apply -f ${SCRIPT_DIR}/k8s/02-dev-statefulset.yaml

    # Wait for statefulset to be ready
    log_info "Waiting for development pod to be ready..."
    kubectl rollout status statefulset/ml-dev -n ${NAMESPACE} --timeout=600s

    log_success "Kubernetes resources deployed successfully"
}

# Get connection info
get_connection_info() {
    log_info "Getting connection information..."

    echo
    log_success "=== Connection Information ==="
    echo
    echo "Port-forward commands:"
    echo "  kubectl port-forward -n ${NAMESPACE} svc/ml-dev 2222:22 8888:8888 6006:6006"
    echo "  # Or use: ./port-forward.sh start"
    echo
    echo "SSH Access (after port-forward):"
    echo "  ssh ${DEV_USER}@localhost -p 2222"
    echo
    echo "SSH Config Entry (~/.ssh/config):"
    echo "  Host ml-dev"
    echo "    HostName localhost"
    echo "    Port 2222"
    echo "    User ${DEV_USER}"
    echo "    IdentityFile ~/.ssh/id_ed25519"
    echo
    echo "Services (after port-forward):"
    echo "  Jupyter:     http://localhost:8888"
    echo "  TensorBoard: http://localhost:6006"
    echo
    echo "Zed Remote SSH:"
    echo "  File → Open → Remote via SSH → dev@ml-dev:/workspace"
    echo

    # Copy hello world test scripts
    log_info "Copying test scripts to workspace..."

    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=ml-dev -o jsonpath='{.items[0].metadata.name}')
    kubectl cp ${SCRIPT_DIR}/examples/hello_gpu.py ${NAMESPACE}/${POD_NAME}:/workspace/hello_gpu.py
    kubectl cp ${SCRIPT_DIR}/examples/test_multigpu.py ${NAMESPACE}/${POD_NAME}:/workspace/test_multigpu.py

    log_success "Test scripts copied to /workspace/"
    echo
    echo "Quick GPU tests:"
    echo "  ./test-gpu.sh hello       # Test single GPU"
    echo "  ./test-gpu.sh multigpu    # Test 8 GPUs"
    echo "  ./test-gpu.sh interactive # Run in dev pod"
}

# Main execution
main() {
    log_info "Starting DevPod K8s ML Environment Setup"
    echo
    log_info "Configuration:"
    echo "  Registry: ${REGISTRY}"
    echo "  Org: ${ORG}"
    echo "  Image: ${FULL_IMAGE}"
    echo "  Namespace: ${NAMESPACE}"
    echo

    check_prerequisites

    # Ask what to do
    echo "What would you like to do?"
    echo "1) Full setup (SSH keys + build image + deploy)"
    echo "2) Setup SSH keys only"
    echo "3) Build and update image only"
    echo "4) Deploy Kubernetes resources only"
    echo "5) Get connection info only"
    read -p "Select option (1-5): " -n 1 -r
    echo

    case $REPLY in
        1)
            setup_ssh_keys
            build_image
            deploy_k8s
            get_connection_info
            ;;
        2)
            setup_ssh_keys
            ;;
        3)
            build_image
            ;;
        4)
            deploy_k8s
            get_connection_info
            ;;
        5)
            get_connection_info
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac

    echo
    log_success "Setup completed!"
    log_info "You can now connect to your development environment and start coding!"
}

# Run main function
main "$@"
