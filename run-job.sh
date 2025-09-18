#!/bin/bash
set -e

# Job Runner Script for PyTorch Training on Kubernetes
# Makes it easy to submit training jobs with different configurations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ml"

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

show_help() {
    cat << EOF
PyTorch Training Job Runner

USAGE:
    $0 [OPTIONS] COMMAND

COMMANDS:
    submit          Submit a new training job
    list           List all training jobs
    logs           Show logs for a job
    status         Show status of a job
    delete         Delete a job
    cleanup        Delete completed jobs

OPTIONS:
    -n, --name NAME        Job name (default: auto-generated)
    -g, --gpus GPUS        Number of GPUs (0, 1, 4, 8)
    -e, --epochs EPOCHS    Number of training epochs
    -b, --batch-size SIZE  Batch size
    -l, --lr RATE          Learning rate
    --cpu                  Force CPU-only training
    --image IMAGE          Docker image to use
    --script SCRIPT        Training script path (default: /workspace/train.py)
    --dry-run              Show generated YAML without applying
    -h, --help             Show this help

EXAMPLES:
    # Submit 8-GPU job with custom parameters
    $0 submit -g 8 -e 50 -b 64 -l 0.01

    # Submit single GPU job
    $0 submit -g 1 -e 10

    # Submit CPU-only job for testing
    $0 submit --cpu -e 5

    # Show logs for a job
    $0 logs pytorch-train-8gpu

    # List all jobs
    $0 list

    # Clean up completed jobs
    $0 cleanup
EOF
}

# Generate job name
generate_job_name() {
    local gpus=$1
    local timestamp=$(date +%m%d-%H%M)

    if [[ $gpus -eq 0 ]]; then
        echo "train-cpu-${timestamp}"
    else
        echo "train-${gpus}gpu-${timestamp}"
    fi
}

# Create job YAML
create_job_yaml() {
    local job_name=$1
    local gpus=$2
    local epochs=$3
    local batch_size=$4
    local lr=$5
    local image=$6
    local script=$7

    # Determine resource requests based on GPU count
    local cpu_request="4"
    local memory_request="16Gi"
    local cpu_limit="8"
    local memory_limit="32Gi"

    if [[ $gpus -eq 8 ]]; then
        cpu_request="16"
        memory_request="64Gi"
        cpu_limit="32"
        memory_limit="128Gi"
    elif [[ $gpus -eq 4 ]]; then
        cpu_request="8"
        memory_request="32Gi"
        cpu_limit="16"
        memory_limit="64Gi"
    fi

    # Generate CUDA_VISIBLE_DEVICES
    local cuda_devices="0"
    if [[ $gpus -gt 1 ]]; then
        cuda_devices=$(seq -s, 0 $((gpus-1)))
    fi

    cat << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-training
    gpus: "${gpus}"
    created-by: job-runner
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app: pytorch-training
        gpus: "${gpus}"
        job-name: ${job_name}
    spec:
      restartPolicy: Never
      containers:
      - name: trainer
        image: ${image}
        command: ["bash", "-c"]
        args:
        - |
          set -e
          echo "=== PyTorch Training Job ==="
          echo "Job: ${job_name}"
          echo "GPUs: ${gpus}"
          echo "Epochs: ${epochs}"
          echo "Batch Size: ${batch_size}"
          echo "Learning Rate: ${lr}"
          echo "Script: ${script}"
          echo "=========================="

          if [[ ${gpus} -gt 1 ]]; then
            echo "Starting distributed training with ${gpus} GPUs"
            torchrun \\
              --standalone \\
              --nnodes=1 \\
              --nproc_per_node=${gpus} \\
              ${script} \\
              --data-dir /data \\
              --output-dir /outputs/${job_name} \\
              --epochs ${epochs} \\
              --batch-size ${batch_size} \\
              --lr ${lr}
          else
            echo "Starting single process training"
            python ${script} \\
              --data-dir /data \\
              --output-dir /outputs/${job_name} \\
              --epochs ${epochs} \\
              --batch-size ${batch_size} \\
              --lr ${lr} \\
              $(if [[ ${gpus} -eq 0 ]]; then echo "--device cpu"; fi)
          fi

        env:
        - name: PYTHONPATH
          value: "/workspace"
        $(if [[ $gpus -gt 0 ]]; then cat << ENV
        - name: CUDA_VISIBLE_DEVICES
          value: "${cuda_devices}"
        - name: NCCL_DEBUG
          value: "INFO"
        - name: NCCL_P2P_DISABLE
          value: "0"
        - name: NCCL_IB_DISABLE
          value: "1"
ENV
        fi)

        resources:
          requests:
            cpu: "${cpu_request}"
            memory: "${memory_request}"
            $(if [[ $gpus -gt 0 ]]; then echo "nvidia.com/gpu: ${gpus}"; fi)
          limits:
            cpu: "${cpu_limit}"
            memory: "${memory_limit}"
            $(if [[ $gpus -gt 0 ]]; then echo "nvidia.com/gpu: ${gpus}"; fi)

        volumeMounts:
        - name: workspace
          mountPath: /workspace
        - name: datasets
          mountPath: /data
          readOnly: true
        - name: outputs
          mountPath: /outputs
        - name: cache
          mountPath: /root/.cache

      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: ml-workspace
      - name: datasets
        persistentVolumeClaim:
          claimName: ml-datasets
      - name: outputs
        persistentVolumeClaim:
          claimName: ml-outputs
      - name: cache
        persistentVolumeClaim:
          claimName: ml-cache
EOF
}

# Submit job
submit_job() {
    local job_name=""
    local gpus=1
    local epochs=10
    local batch_size=32
    local lr=0.001
    local image="pytorch-dev:latest"
    local script="/workspace/train.py"
    local dry_run=false
    local force_cpu=false

    # Parse submit command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                job_name="$2"
                shift 2
                ;;
            -g|--gpus)
                gpus="$2"
                shift 2
                ;;
            -e|--epochs)
                epochs="$2"
                shift 2
                ;;
            -b|--batch-size)
                batch_size="$2"
                shift 2
                ;;
            -l|--lr)
                lr="$2"
                shift 2
                ;;
            --image)
                image="$2"
                shift 2
                ;;
            --script)
                script="$2"
                shift 2
                ;;
            --cpu)
                force_cpu=true
                gpus=0
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Force CPU if requested
    if [[ $force_cpu == true ]]; then
        gpus=0
    fi

    # Validate GPU count
    if [[ ! $gpus =~ ^[0-9]+$ ]] || [[ $gpus -lt 0 ]] || [[ $gpus -gt 8 ]]; then
        log_error "Invalid GPU count: $gpus. Must be 0-8"
        exit 1
    fi

    # Generate job name if not provided
    if [[ -z $job_name ]]; then
        job_name=$(generate_job_name $gpus)
    fi

    log_info "Preparing job: $job_name"
    log_info "Configuration:"
    echo "  GPUs: $gpus"
    echo "  Epochs: $epochs"
    echo "  Batch Size: $batch_size"
    echo "  Learning Rate: $lr"
    echo "  Image: $image"
    echo "  Script: $script"

    # Create job YAML
    local yaml_content=$(create_job_yaml "$job_name" "$gpus" "$epochs" "$batch_size" "$lr" "$image" "$script")

    if [[ $dry_run == true ]]; then
        echo
        log_info "Generated YAML (dry-run):"
        echo "$yaml_content"
        return 0
    fi

    # Apply job
    echo "$yaml_content" | kubectl apply -f -

    log_success "Job submitted: $job_name"
    log_info "Monitor with: $0 logs $job_name"
}

# List jobs
list_jobs() {
    echo
    log_info "Training Jobs in namespace: $NAMESPACE"
    echo
    kubectl get jobs -n $NAMESPACE -l app=pytorch-training \
        -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[0].type,GPUS:.metadata.labels.gpus,AGE:.metadata.creationTimestamp" \
        --sort-by=.metadata.creationTimestamp
}

# Show job logs
show_logs() {
    local job_name=$1
    if [[ -z $job_name ]]; then
        log_error "Job name required"
        exit 1
    fi

    log_info "Showing logs for job: $job_name"
    kubectl logs -f job/$job_name -n $NAMESPACE
}

# Show job status
show_status() {
    local job_name=$1
    if [[ -z $job_name ]]; then
        log_error "Job name required"
        exit 1
    fi

    log_info "Status for job: $job_name"
    kubectl describe job/$job_name -n $NAMESPACE
}

# Delete job
delete_job() {
    local job_name=$1
    if [[ -z $job_name ]]; then
        log_error "Job name required"
        exit 1
    fi

    log_info "Deleting job: $job_name"
    kubectl delete job/$job_name -n $NAMESPACE
    log_success "Job deleted: $job_name"
}

# Cleanup completed jobs
cleanup_jobs() {
    log_info "Cleaning up completed jobs..."

    # Delete jobs with status Complete or Failed
    local completed_jobs=$(kubectl get jobs -n $NAMESPACE -l app=pytorch-training \
        -o jsonpath='{.items[?(@.status.conditions[0].type=="Complete")].metadata.name}' 2>/dev/null)
    local failed_jobs=$(kubectl get jobs -n $NAMESPACE -l app=pytorch-training \
        -o jsonpath='{.items[?(@.status.conditions[0].type=="Failed")].metadata.name}' 2>/dev/null)

    if [[ -n "$completed_jobs" ]]; then
        for job in $completed_jobs; do
            log_info "Deleting completed job: $job"
            kubectl delete job/$job -n $NAMESPACE
        done
    fi

    if [[ -n "$failed_jobs" ]]; then
        for job in $failed_jobs; do
            log_info "Deleting failed job: $job"
            kubectl delete job/$job -n $NAMESPACE
        done
    fi

    if [[ -z "$completed_jobs" && -z "$failed_jobs" ]]; then
        log_info "No completed jobs to clean up"
    else
        log_success "Cleanup completed"
    fi
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    local command=$1
    shift

    case $command in
        submit)
            submit_job "$@"
            ;;
        list)
            list_jobs
            ;;
        logs)
            show_logs "$@"
            ;;
        status)
            show_status "$@"
            ;;
        delete)
            delete_job "$@"
            ;;
        cleanup)
            cleanup_jobs
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
