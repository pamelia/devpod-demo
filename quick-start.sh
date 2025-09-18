#!/bin/bash
set -e

# DevPod K8s ML Quick Start
# Complete setup for PyTorch development environment on Kubernetes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

show_banner() {
    echo
    echo "🚀 DevPod K8s ML Quick Start"
    echo "=============================="
    echo "Complete PyTorch development environment on Kubernetes"
    echo "- Persistent workspace with SSH access"
    echo "- GPU support for training"
    echo "- Remote editing with Zed/VS Code"
    echo "- Easy job submission"
    echo
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl")
    fi

    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo "Please install them and try again."
        exit 1
    fi

    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "Make sure kubectl is configured and cluster is accessible."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

configure_setup() {
    log_info "Configuration setup..."

    # Check if config.env exists and has been customized
    if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
        if grep -q "yourorg" "${SCRIPT_DIR}/config.env"; then
            log_warning "config.env contains default 'yourorg' value"
            echo "Edit config.env to set your GitHub organization:"
            echo "  ORG=\"your-github-org\""
            echo
            read -p "Continue with default values? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Please edit config.env and run this script again"
                exit 1
            fi
        fi
    else
        log_error "config.env not found"
        exit 1
    fi

    log_success "Configuration ready"
}

setup_ssh_keys() {
    log_info "Setting up SSH keys..."

    if [[ ! -f ~/.ssh/id_ed25519.pub ]]; then
        log_warning "SSH key not found at ~/.ssh/id_ed25519.pub"
        read -p "Generate new SSH key? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ssh-keygen -t ed25519 -C "devpod-k8s-ml" -f ~/.ssh/id_ed25519 -N ""
            log_success "SSH key generated"
        else
            log_error "SSH key required for setup"
            exit 1
        fi
    fi

    log_success "SSH keys ready"
}

build_and_deploy() {
    log_info "Building and deploying..."

    # Run the main setup script
    "${SCRIPT_DIR}/setup.sh" <<< "1"

    log_success "Build and deployment completed"
}

start_port_forward() {
    log_info "Starting port-forward..."

    # Wait a moment for pod to be fully ready
    sleep 5

    "${SCRIPT_DIR}/port-forward.sh" start

    log_success "Port-forward established"
}

show_next_steps() {
    echo
    log_success "🎉 Setup Complete!"
    echo
    echo "=== Next Steps ==="
    echo
    echo "1. Test SSH connection:"
    echo "   ssh dev@localhost -p 2222"
    echo
    echo "2. Add SSH config entry (~/.ssh/config):"
    echo "   Host ml-dev"
    echo "     HostName localhost"
    echo "     Port 2222"
    echo "     User dev"
    echo "     IdentityFile ~/.ssh/id_ed25519"
    echo "     StrictHostKeyChecking no"
    echo "     UserKnownHostsFile /dev/null"
    echo "     LogLevel ERROR"
    echo
    echo "3. Connect with Zed:"
    echo "   File → Open → Remote via SSH → dev@ml-dev:/workspace"
    echo
    echo "4. Access services:"
    echo "   Jupyter:     http://localhost:8888"
    echo "   TensorBoard: http://localhost:6006"
    echo
    echo "5. Submit training jobs:"
    echo "   ./run-job.sh submit -g 8 -e 50    # 8-GPU training"
    echo "   ./run-job.sh submit -g 1 -e 10    # Single GPU"
    echo "   ./run-job.sh submit --cpu         # CPU-only"
    echo
    echo "6. Monitor jobs:"
    echo "   ./run-job.sh list"
    echo "   ./run-job.sh logs <job-name>"
    echo
    echo "=== Useful Commands ==="
    echo "   ./port-forward.sh status    # Check port-forward status"
    echo "   ./port-forward.sh restart   # Restart port-forward"
    echo "   kubectl get pods -n ml      # Check pod status"
    echo
    log_info "Happy coding! 🚀"
}

cleanup_on_error() {
    log_error "Setup failed. Cleaning up..."
    "${SCRIPT_DIR}/port-forward.sh" stop 2>/dev/null || true
}

main() {
    # Set up error handling
    trap cleanup_on_error ERR

    show_banner
    check_prerequisites
    configure_setup
    setup_ssh_keys
    build_and_deploy
    start_port_forward
    show_next_steps
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "DevPod K8s ML Quick Start"
    echo
    echo "This script performs a complete setup:"
    echo "1. Checks prerequisites (kubectl, docker)"
    echo "2. Validates configuration in config.env"
    echo "3. Sets up SSH keys if needed"
    echo "4. Builds Docker image and deploys to K8s"
    echo "5. Starts port-forwarding for SSH access"
    echo
    echo "Usage: $0"
    echo
    echo "Before running:"
    echo "- Edit config.env with your GitHub org"
    echo "- Ensure kubectl is connected to your cluster"
    echo "- Ensure Docker is running"
    exit 0
fi

# Run main function
main "$@"
