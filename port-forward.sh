#!/bin/bash
set -e

# DevPod K8s ML Port-Forward Helper
# Establishes port-forwarding for SSH, Jupyter, and TensorBoard access

NAMESPACE="ml"
SERVICE="ml-dev"

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

# Check if pod is ready
check_pod_ready() {
    log_info "Checking if development pod is ready..."

    if ! kubectl get pods -n ${NAMESPACE} -l app=ml-dev | grep -q Running; then
        log_error "Development pod is not running. Deploy it first with:"
        echo "  kubectl apply -f k8s/02-dev-statefulset.yaml"
        exit 1
    fi

    log_success "Development pod is running"
}

# Start port forwarding
start_port_forward() {
    log_info "Starting port-forward..."

    # Kill any existing port-forwards on these ports
    pkill -f "kubectl.*port-forward.*ml-dev" 2>/dev/null || true
    sleep 1

    # Start port forwarding in background
    kubectl port-forward -n ${NAMESPACE} svc/${SERVICE} 2222:22 8888:8888 6006:6006 &
    PF_PID=$!

    # Wait a moment for port-forward to establish
    sleep 3

    # Check if port-forward is working
    if ps -p $PF_PID > /dev/null; then
        log_success "Port-forward established (PID: $PF_PID)"
        echo
        log_info "=== Connection Information ==="
        echo
        echo "SSH Access:"
        echo "  ssh dev@localhost -p 2222"
        echo
        echo "SSH Config Entry (~/.ssh/config):"
        echo "  Host ml-dev"
        echo "    HostName localhost"
        echo "    Port 2222"
        echo "    User dev"
        echo "    IdentityFile ~/.ssh/id_ed25519"
        echo "    StrictHostKeyChecking no"
        echo "    UserKnownHostsFile /dev/null"
        echo "    LogLevel ERROR"
        echo
        echo "Services:"
        echo "  Jupyter:     http://localhost:8888"
        echo "  TensorBoard: http://localhost:6006"
        echo
        echo "Zed Remote SSH:"
        echo "  File → Open → Remote via SSH → dev@ml-dev:/workspace"
        echo
        log_warning "Port-forward running in background (PID: $PF_PID)"
        echo "To stop: kill $PF_PID or run: $0 stop"

        # Save PID for stop command
        echo $PF_PID > /tmp/ml-dev-port-forward.pid
    else
        log_error "Failed to establish port-forward"
        exit 1
    fi
}

# Stop port forwarding
stop_port_forward() {
    log_info "Stopping port-forward..."

    # Try to kill by saved PID first
    if [[ -f /tmp/ml-dev-port-forward.pid ]]; then
        PF_PID=$(cat /tmp/ml-dev-port-forward.pid)
        if ps -p $PF_PID > /dev/null; then
            kill $PF_PID
            log_success "Stopped port-forward (PID: $PF_PID)"
        fi
        rm -f /tmp/ml-dev-port-forward.pid
    fi

    # Kill any remaining kubectl port-forward processes for ml-dev
    pkill -f "kubectl.*port-forward.*ml-dev" 2>/dev/null && log_success "Cleaned up any remaining port-forwards" || log_info "No port-forwards found"
}

# Show status
show_status() {
    echo
    log_info "=== Port-Forward Status ==="
    echo

    if [[ -f /tmp/ml-dev-port-forward.pid ]]; then
        PF_PID=$(cat /tmp/ml-dev-port-forward.pid)
        if ps -p $PF_PID > /dev/null; then
            log_success "Port-forward is running (PID: $PF_PID)"
            echo
            echo "Active connections:"
            echo "  SSH:        localhost:2222"
            echo "  Jupyter:    localhost:8888"
            echo "  TensorBoard: localhost:6006"
            echo
            echo "Test SSH: ssh dev@localhost -p 2222"
        else
            log_warning "Stale PID file found, cleaning up..."
            rm -f /tmp/ml-dev-port-forward.pid
            log_info "Port-forward is not running"
        fi
    else
        log_info "Port-forward is not running"

        # Check for orphaned processes
        if pgrep -f "kubectl.*port-forward.*ml-dev" > /dev/null; then
            log_warning "Found orphaned port-forward processes"
            echo "Clean up with: $0 stop"
        fi
    fi

    echo
    log_info "Pod status:"
    kubectl get pods -n ${NAMESPACE} -l app=ml-dev -o wide 2>/dev/null || log_error "Could not get pod status"
}

# Show help
show_help() {
    echo "DevPod K8s ML Port-Forward Helper"
    echo
    echo "USAGE:"
    echo "  $0 [COMMAND]"
    echo
    echo "COMMANDS:"
    echo "  start     Start port-forwarding (default)"
    echo "  stop      Stop port-forwarding"
    echo "  restart   Restart port-forwarding"
    echo "  status    Show port-forward status"
    echo "  help      Show this help"
    echo
    echo "EXAMPLES:"
    echo "  $0              # Start port-forwarding"
    echo "  $0 start        # Start port-forwarding"
    echo "  $0 stop         # Stop port-forwarding"
    echo "  $0 status       # Check status"
    echo
    echo "After starting, you can:"
    echo "  - SSH: ssh dev@localhost -p 2222"
    echo "  - Use Zed remote: dev@ml-dev:/workspace"
    echo "  - Access Jupyter: http://localhost:8888"
    echo "  - Access TensorBoard: http://localhost:6006"
}

# Main execution
main() {
    case "${1:-start}" in
        start)
            check_pod_ready
            start_port_forward
            ;;
        stop)
            stop_port_forward
            ;;
        restart)
            stop_port_forward
            sleep 1
            check_pod_ready
            start_port_forward
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
