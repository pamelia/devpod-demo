#!/bin/bash
set -e

# Simple GPU Test Job Runner
# Quick tests to verify PyTorch and GPU functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    echo "🚀 GPU Test Job Runner"
    echo
    echo "USAGE:"
    echo "  $0 [COMMAND]"
    echo
    echo "COMMANDS:"
    echo "  hello         Test single GPU (hello world)"
    echo "  multigpu      Test all 8 GPUs with DDP"
    echo "  cpu           Test CPU-only mode"
    echo "  interactive   Run interactive test in dev pod"
    echo "  logs JOB      Show logs for test job"
    echo "  cleanup       Delete test jobs"
    echo "  list          List test jobs"
    echo
    echo "EXAMPLES:"
    echo "  $0 hello              # Test single GPU"
    echo "  $0 multigpu           # Test 8-GPU setup"
    echo "  $0 interactive        # Run test in dev pod"
    echo "  $0 logs hello-gpu     # Show job logs"
    echo
    echo "These are simple 'hello world' tests that verify:"
    echo "  ✅ PyTorch installation"
    echo "  ✅ GPU availability and memory"
    echo "  ✅ CUDA functionality"
    echo "  ✅ Multi-GPU communication (DDP)"
    echo "  ✅ Tensor operations"
}

run_hello_job() {
    log_info "Submitting single GPU hello world job..."

    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-gpu
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-test
    type: hello-world
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: hello-gpu
        image: ${FULL_IMAGE}
        command: ["python", "/workspace/hello_gpu.py"]
        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "0"
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
            nvidia.com/gpu: 1
          limits:
            cpu: "2"
            memory: "4Gi"
            nvidia.com/gpu: 1
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: ml-workspace
EOF

    log_success "Hello GPU job submitted!"
    log_info "Monitor with: $0 logs hello-gpu"
}

run_multigpu_job() {
    log_info "Submitting 8-GPU multi-GPU test job..."

    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-multigpu
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-test
    type: multi-gpu
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: hello-multigpu
        image: ${FULL_IMAGE}
        command: ["python", "/workspace/test_multigpu.py"]
        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "0,1,2,3,4,5,6,7"
        resources:
          requests:
            cpu: "8"
            memory: "16Gi"
            nvidia.com/gpu: 8
          limits:
            cpu: "16"
            memory: "32Gi"
            nvidia.com/gpu: 8
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: ml-workspace
EOF

    log_success "Multi-GPU test job submitted!"
    log_info "Monitor with: $0 logs hello-multigpu"
}

run_cpu_job() {
    log_info "Submitting CPU-only test job..."

    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-cpu
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-test
    type: cpu-only
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 1800
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: hello-cpu
        image: ${FULL_IMAGE}
        command: ["python", "/workspace/hello_gpu.py"]
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: ml-workspace
EOF

    log_success "CPU test job submitted!"
    log_info "Monitor with: $0 logs hello-cpu"
}

run_interactive() {
    log_info "Running interactive GPU test in dev pod..."

    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=ml-dev -o jsonpath='{.items[0].metadata.name}')

    if [[ -z "$POD_NAME" ]]; then
        log_error "Dev pod not found. Deploy it first with: kubectl apply -f k8s/02-dev-statefulset.yaml"
        exit 1
    fi

    log_info "Running test in pod: $POD_NAME"
    kubectl exec -it -n ${NAMESPACE} $POD_NAME -- python /workspace/hello_gpu.py
}

show_logs() {
    local job_name=$1
    if [[ -z "$job_name" ]]; then
        log_error "Job name required. Use: $0 logs <job-name>"
        exit 1
    fi

    log_info "Showing logs for job: $job_name"
    kubectl logs -f job/$job_name -n ${NAMESPACE}
}

list_jobs() {
    log_info "Test jobs in namespace: ${NAMESPACE}"
    echo
    kubectl get jobs -n ${NAMESPACE} -l app=pytorch-test \
        -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[0].type,TYPE:.metadata.labels.type,AGE:.metadata.creationTimestamp" \
        --sort-by=.metadata.creationTimestamp
}

cleanup_jobs() {
    log_info "Cleaning up test jobs..."

    kubectl delete jobs -n ${NAMESPACE} -l app=pytorch-test --ignore-not-found=true

    log_success "Test jobs cleaned up"
}

copy_test_scripts() {
    log_info "Copying test scripts to workspace..."

    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=ml-dev -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$POD_NAME" ]]; then
        kubectl cp ${SCRIPT_DIR}/examples/hello_gpu.py ${NAMESPACE}/${POD_NAME}:/workspace/hello_gpu.py
        kubectl cp ${SCRIPT_DIR}/examples/test_multigpu.py ${NAMESPACE}/${POD_NAME}:/workspace/test_multigpu.py
        log_success "Test scripts copied to /workspace/"
    else
        log_warning "Dev pod not found - scripts will be copied when pod is created"
    fi
}

main() {
    case "${1:-help}" in
        hello)
            copy_test_scripts
            run_hello_job
            ;;
        multigpu)
            copy_test_scripts
            run_multigpu_job
            ;;
        cpu)
            copy_test_scripts
            run_cpu_job
            ;;
        interactive)
            copy_test_scripts
            run_interactive
            ;;
        logs)
            show_logs "$2"
            ;;
        list)
            list_jobs
            ;;
        cleanup)
            cleanup_jobs
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
