#!/bin/bash
set -e

# Generate Kubernetes manifests from templates using config.env
# This script creates all manifests with the correct registry/org settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

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

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    log_info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"

    # Validate required variables
    local required_vars=("REGISTRY" "ORG" "IMAGE_NAME" "IMAGE_TAG" "NAMESPACE")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required variable $var is not set in $CONFIG_FILE"
            exit 1
        fi
    done

    log_success "Configuration loaded successfully"
    echo "  Registry: $REGISTRY"
    echo "  Org: $ORG"
    echo "  Image: $IMAGE_NAME:$IMAGE_TAG"
    echo "  Full Image: $FULL_IMAGE"
}

# Generate storage manifest
generate_storage() {
    log_info "Generating storage manifest..."

    cat > "${SCRIPT_DIR}/k8s/01-storage.yaml" << EOF
# Generated storage manifest - DO NOT EDIT MANUALLY
# Edit config.env and run generate-manifests.sh instead

# Namespace for ML workloads
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
# Persistent workspace - your code lives here, survives pod restarts
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-workspace
  namespace: ${NAMESPACE}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: ${WORKSPACE_SIZE}
  # storageClassName: local-path  # uncomment if using k3s default
---
# Datasets storage - mount your training data here
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-datasets
  namespace: ${NAMESPACE}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: ${DATASETS_SIZE}
  # storageClassName: local-path
---
# Outputs storage - model checkpoints, logs, artifacts
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-outputs
  namespace: ${NAMESPACE}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: ${OUTPUTS_SIZE}
  # storageClassName: local-path
---
# Shared cache - pip cache, huggingface models, etc
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-cache
  namespace: ${NAMESPACE}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: ${CACHE_SIZE}
  # storageClassName: local-path
EOF
}

# Generate dev pod manifest
generate_dev_pod() {
    log_info "Generating development pod manifest..."

    cat > "${SCRIPT_DIR}/k8s/02-dev-statefulset.yaml" << EOF
# Generated dev pod manifest - DO NOT EDIT MANUALLY
# Edit config.env and run generate-manifests.sh instead

# Development StatefulSet with SSH access and GPU support
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ml-dev
  namespace: ${NAMESPACE}
  labels:
    app: ml-dev
spec:
  serviceName: ml-dev
  replicas: 1
  selector:
    matchLabels:
      app: ml-dev
  template:
    metadata:
      labels:
        app: ml-dev
    spec:
      # Schedule on GPU nodes
      nodeSelector:
        node.coreweave.cloud/class: gpu

      # Security context for GPU access - match working Slurm config
      securityContext:
        seccompProfile:
          localhostProfile: profiles/enroot
          type: Localhost

      containers:
        - name: dev
          image: ${FULL_IMAGE}
          imagePullPolicy: Always

          # Security context for container - match working Slurm config
          securityContext:
            capabilities:
              add:
                - SYS_NICE
                - SYS_ADMIN
                - SYS_PTRACE
                - SYSLOG
            appArmorProfile:
              localhostProfile: enroot
              type: Localhost

          ports:
            - containerPort: 22
              name: ssh
            - containerPort: 8888
              name: jupyter
            - containerPort: 6006
              name: tensorboard

          env:
            # Make all GPUs visible by default (adjust as needed)
            - name: NVIDIA_VISIBLE_DEVICES
              value: "all"
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: "all"
            - name: NVIDIA_GDRCOPY
              value: "enabled"
            - name: PYTHONPATH
              value: "/workspace"

          resources:
            requests:
              cpu: "${DEFAULT_CPU_REQUEST}"
              memory: "${DEFAULT_MEMORY_REQUEST}"
              # Request 1 GPU for interactive development
              nvidia.com/gpu: ${DEFAULT_DEV_GPU_LIMIT}
            limits:
              cpu: "8"
              memory: "32Gi"
              # Limit to 1 GPU for dev work (training jobs can use more)
              nvidia.com/gpu: ${DEFAULT_DEV_GPU_LIMIT}

          volumeMounts:
            # Persistent workspace - your code lives here
            - name: workspace
              mountPath: ${WORKSPACE_PATH}
            # Datasets mount
            - name: datasets
              mountPath: ${DATA_PATH}
            # Outputs mount
            - name: outputs
              mountPath: ${OUTPUTS_PATH}
            # Cache mount for pip, huggingface, etc
            - name: cache
              mountPath: /home/${DEV_USER}/.cache
            # SSH keys from secret
            - name: ssh-keys
              mountPath: /ssh-keys
              readOnly: true

          # Health checks
          livenessProbe:
            tcpSocket:
              port: 22
            initialDelaySeconds: 30
            periodSeconds: 30

          readinessProbe:
            tcpSocket:
              port: 22
            initialDelaySeconds: 10
            periodSeconds: 10

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
        - name: ssh-keys
          secret:
            secretName: ${SSH_KEY_SECRET}
            defaultMode: 0600

---
# ClusterIP service for port-forward access
apiVersion: v1
kind: Service
metadata:
  name: ml-dev
  namespace: ${NAMESPACE}
  labels:
    app: ml-dev
spec:
  type: ${SERVICE_TYPE}
  selector:
    app: ml-dev
  ports:
    - name: ssh
      port: 22
      targetPort: 22
    - name: jupyter
      port: 8888
      targetPort: 8888
    - name: tensorboard
      port: 6006
      targetPort: 6006
EOF
}

# Generate training job manifest
generate_training_jobs() {
    log_info "Generating training job manifests..."

    cat > "${SCRIPT_DIR}/k8s/03-training-job.yaml" << EOF
# Generated training job manifest - DO NOT EDIT MANUALLY
# Edit config.env and run generate-manifests.sh instead

# Training job template for single-node multi-GPU PyTorch training
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-train-8gpu
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-training
    gpus: "8"
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 86400  # Keep job for 24h after completion
  template:
    metadata:
      labels:
        app: pytorch-training
        gpus: "8"
    spec:
      restartPolicy: Never

      # Schedule on GPU nodes
      nodeSelector:
        node.coreweave.cloud/class: gpu

      containers:
      - name: trainer
        image: ${FULL_IMAGE}

        command: ["bash", "-c"]
        args:
        - |
          set -e
          echo "Starting PyTorch DDP training with \$GPUS GPUs"
          echo "CUDA devices visible: \$CUDA_VISIBLE_DEVICES"
          echo "Available GPUs: \$(python -c 'import torch; print(torch.cuda.device_count())')"

          # Run distributed training
          torchrun \\
            --standalone \\
            --nnodes=1 \\
            --nproc_per_node=\$GPUS \\
            ${WORKSPACE_PATH}/hello_gpu.py \\
            --data-dir ${DATA_PATH} \\
            --output-dir ${OUTPUTS_PATH} \\
            --epochs ${DEFAULT_EPOCHS} \\
            --batch-size ${DEFAULT_BATCH_SIZE} \\
            --lr ${DEFAULT_LEARNING_RATE}

        env:
        - name: GPUS
          value: "8"
        - name: CUDA_VISIBLE_DEVICES
          value: "0,1,2,3,4,5,6,7"
        - name: NCCL_DEBUG
          value: "INFO"
        - name: NCCL_P2P_DISABLE
          value: "0"  # Enable P2P for better performance
        - name: NCCL_IB_DISABLE
          value: "1"  # Disable InfiniBand if not available
        - name: PYTHONPATH
          value: "${WORKSPACE_PATH}"
        - name: WANDB_MODE
          value: "offline"  # Set to "online" if you want to log to wandb

        resources:
          requests:
            cpu: "16"
            memory: "64Gi"
            nvidia.com/gpu: 8
          limits:
            cpu: "32"
            memory: "128Gi"
            nvidia.com/gpu: 8

        volumeMounts:
        - name: workspace
          mountPath: ${WORKSPACE_PATH}
        - name: datasets
          mountPath: ${DATA_PATH}
          readOnly: true
        - name: outputs
          mountPath: ${OUTPUTS_PATH}
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

---
# Single GPU training job for experimentation
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-train-1gpu
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-training
    gpus: "1"
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 3600  # Keep job for 1h after completion
  template:
    metadata:
      labels:
        app: pytorch-training
        gpus: "1"
    spec:
      restartPolicy: Never

      containers:
      - name: trainer
        image: ${FULL_IMAGE}

        command: ["bash", "-c"]
        args:
        - |
          set -e
          echo "Starting single GPU training"
          echo "CUDA device: \$CUDA_VISIBLE_DEVICES"

          python ${WORKSPACE_PATH}/hello_gpu.py \\
            --data-dir ${DATA_PATH} \\
            --output-dir ${OUTPUTS_PATH} \\
            --epochs ${DEFAULT_EPOCHS} \\
            --batch-size ${DEFAULT_BATCH_SIZE} \\
            --lr ${DEFAULT_LEARNING_RATE}

        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTHONPATH
          value: "${WORKSPACE_PATH}"

        resources:
          requests:
            cpu: "4"
            memory: "16Gi"
            nvidia.com/gpu: 1
          limits:
            cpu: "8"
            memory: "32Gi"
            nvidia.com/gpu: 1

        volumeMounts:
        - name: workspace
          mountPath: ${WORKSPACE_PATH}
        - name: datasets
          mountPath: ${DATA_PATH}
          readOnly: true
        - name: outputs
          mountPath: ${OUTPUTS_PATH}
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

---
# CPU-only training job for testing
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-train-cpu
  namespace: ${NAMESPACE}
  labels:
    app: pytorch-training
    gpus: "0"
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 1800  # Keep job for 30min after completion
  template:
    metadata:
      labels:
        app: pytorch-training
        gpus: "0"
    spec:
      restartPolicy: Never

      containers:
      - name: trainer
        image: ${FULL_IMAGE}

        command: ["bash", "-c"]
        args:
        - |
          set -e
          echo "Starting CPU-only training"

          python ${WORKSPACE_PATH}/hello_gpu.py \\
            --data-dir ${DATA_PATH} \\
            --output-dir ${OUTPUTS_PATH} \\
            --epochs 5 \\
            --batch-size 8 \\
            --lr ${DEFAULT_LEARNING_RATE} \\
            --device cpu

        env:
        - name: PYTHONPATH
          value: "${WORKSPACE_PATH}"

        resources:
          requests:
            cpu: "8"
            memory: "16Gi"
          limits:
            cpu: "16"
            memory: "32Gi"

        volumeMounts:
        - name: workspace
          mountPath: ${WORKSPACE_PATH}
        - name: datasets
          mountPath: ${DATA_PATH}
          readOnly: true
        - name: outputs
          mountPath: ${OUTPUTS_PATH}
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

# Update setup script to use config
update_setup_script() {
    log_info "Updating setup.sh to use config.env..."

    # Create a temporary setup script that sources config
    cat > "${SCRIPT_DIR}/setup.sh.tmp" << 'EOF'
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
    if [[ ! -f ~/.ssh/id_ed25519.pub ]]; then
        log_warning "SSH key not found at ~/.ssh/id_ed25519.pub"
        read -p "Generate new SSH key? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ssh-keygen -t ed25519 -C "devpod-k8s-ml" -f ~/.ssh/id_ed25519
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
        --from-file=authorized_keys=~/.ssh/id_ed25519.pub \
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

    # Build image
    cd "${SCRIPT_DIR}/docker"
    docker build -t ${image_name} .

    # Ask if user wants to push
    read -p "Push image to registry? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker push ${image_name}
        log_success "Image pushed to registry"
    else
        log_warning "Image not pushed. Make sure image is available to your cluster."
    fi

    log_success "Docker image ready: ${image_name}"
}

# Generate manifests from config
generate_manifests() {
    log_info "Generating manifests from config.env..."
    "${SCRIPT_DIR}/generate-manifests.sh"
}

# Deploy Kubernetes resources
deploy_k8s() {
    log_info "Deploying Kubernetes resources..."

    # Generate fresh manifests
    generate_manifests

    # Apply storage
    log_info "Creating storage..."
    kubectl apply -f ${SCRIPT_DIR}/k8s/01-storage.yaml

    # Wait for PVCs to be bound
    log_info "Waiting for PVCs to be bound..."
    kubectl wait --for=condition=Bound pvc/ml-workspace -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=condition=Bound pvc/ml-datasets -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=condition=Bound pvc/ml-outputs -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=condition=Bound pvc/ml-cache -n ${NAMESPACE} --timeout=300s

    # Deploy dev pod
    log_info "Deploying development pod..."
    kubectl apply -f ${SCRIPT_DIR}/k8s/02-dev-statefulset.yaml

    # Wait for deployment to be ready
    log_info "Waiting for development pod to be ready..."
    kubectl rollout status deployment/ml-dev -n ${NAMESPACE} --timeout=600s

    log_success "Kubernetes resources deployed successfully"
}

# Get connection info
get_connection_info() {
    log_info "Getting connection information..."

    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [[ -z "${NODE_IP}" ]]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi

    echo
    log_success "=== Connection Information ==="
    echo
    echo "Port-forward commands:"
    echo "  kubectl port-forward -n ${NAMESPACE} svc/ml-dev 2222:22 8888:8888 6006:6006"
    echo
    echo "SSH Access (after port-forward):"
    echo "  ssh ${DEV_USER}@localhost -p 2222"
    echo
    echo "SSH Config Entry:"
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
    echo "Background port-forward:"
    echo "  kubectl port-forward -n ${NAMESPACE} svc/ml-dev 2222:22 8888:8888 6006:6006 &"
    echo

    # Copy example training script
    log_info "Copying example training script to workspace..."

    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=ml-dev -o jsonpath='{.items[0].metadata.name}')
    kubectl cp ${SCRIPT_DIR}/examples/hello_gpu.py ${NAMESPACE}/${POD_NAME}:${WORKSPACE_PATH}/hello_gpu.py
    kubectl cp ${SCRIPT_DIR}/examples/test_multigpu.py ${NAMESPACE}/${POD_NAME}:${WORKSPACE_PATH}/test_multigpu.py

    log_success "Test scripts copied to ${WORKSPACE_PATH}/"
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
EOF

    # Replace the original setup.sh
    mv "${SCRIPT_DIR}/setup.sh.tmp" "${SCRIPT_DIR}/setup.sh"
    chmod +x "${SCRIPT_DIR}/setup.sh"
}

# Update run-job.sh to use config
update_run_job_script() {
    log_info "Updating run-job.sh to use config.env..."

    # Add config loading at the top of run-job.sh
    sed -i.bak '1a\
\
# Load configuration\
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\
source "${SCRIPT_DIR}/config.env"\
' "${SCRIPT_DIR}/run-job.sh"

    # Replace hardcoded values in run-job.sh
    sed -i.bak "s/NAMESPACE=\"ml\"/NAMESPACE=\"\${NAMESPACE}\"/g" "${SCRIPT_DIR}/run-job.sh"
    sed -i.bak "s/image=\"pytorch-dev:latest\"/image=\"\${FULL_IMAGE}\"/g" "${SCRIPT_DIR}/run-job.sh"

    # Clean up backup file
    rm -f "${SCRIPT_DIR}/run-job.sh.bak"
}

# Show current configuration
show_config() {
    echo
    log_info "Current Configuration:"
    echo "  Registry: $REGISTRY"
    echo "  Organization: $ORG"
    echo "  Image Name: $IMAGE_NAME"
    echo "  Image Tag: $IMAGE_TAG"
    echo "  Full Image: $FULL_IMAGE"
    echo "  Namespace: $NAMESPACE"
    echo "  SSH NodePort: $SSH_NODEPORT"
    echo "  Jupyter NodePort: $JUPYTER_NODEPORT"
    echo "  TensorBoard NodePort: $TENSORBOARD_NODEPORT"
    echo
}

# Main execution
main() {
    log_info "Kubernetes Manifest Generator"

    if [[ $# -eq 0 ]]; then
        load_config
        show_config

        echo "Actions:"
        echo "1) Generate all manifests"
        echo "2) Generate storage only"
        echo "3) Generate dev pod only"
        echo "4) Generate training jobs only"
        echo "5) Update scripts to use config"
        echo "6) Show configuration"
        read -p "Select action (1-6): " -n 1 -r
        echo

        case $REPLY in
            1)
                generate_storage
                generate_dev_pod
                generate_training_jobs
                log_success "All manifests generated successfully!"
                ;;
            2)
                generate_storage
                log_success "Storage manifest generated!"
                ;;
            3)
                generate_dev_pod
                log_success "Dev pod manifest generated!"
                ;;
            4)
                generate_training_jobs
                log_success "Training job manifests generated!"
                ;;
            5)
                update_setup_script
                update_run_job_script
                log_success "Scripts updated to use config.env!"
                ;;
            6)
                show_config
                ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    else
        # Command line arguments
        case $1 in
            --all)
                load_config
                generate_storage
                generate_dev_pod
                generate_training_jobs
                log_success "All manifests generated!"
                ;;
            --config)
                load_config
                show_config
                ;;
            --help)
                echo "Usage: $0 [--all|--config|--help]"
                echo "  --all     Generate all manifests"
                echo "  --config  Show current configuration"
                echo "  --help    Show this help"
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    fi
}

main "$@"
