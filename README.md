# DevPod on Kubernetes for ML Development

This project demonstrates how to use **DevPod inside a Kubernetes cluster** for PyTorch machine learning development, providing a persistent development environment that doesn't require rebuilding containers for code changes.

## 🎯 What This Solves

- **Persistent Development**: Your code lives in persistent storage, not in the container
- **Remote Development**: SSH access for tools like Zed, VS Code Remote, or terminal
- **GPU Access**: Full access to node GPUs for both interactive development and training jobs
- **Multi-Architecture Support**: Works on both AMD64 and ARM64 GPU nodes (Grace Hopper)
- **No Container Rebuilds**: Iterate on code without rebuilding/pushing containers
- **Shared Resources**: Same data and output volumes across dev environment and training jobs

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│ CoreWeave Kubernetes Cluster           │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────┐  ┌───────────────┐ │
│  │   Dev Pod       │  │ Training Jobs │ │
│  │ - SSH Server    │  │ - 1, 4, 8 GPU │ │
│  │ - PyTorch+CUDA  │  │ - Batch Jobs  │ │
│  │ - 1 GPU         │  │ - Same PVCs   │ │
│  │ - ARM64/AMD64   │  │ - Multi-arch  │ │
│  └─────────────────┘  └───────────────┘ │
│           │                     │       │
│  ┌─────────────────────────────────────┐ │
│  │        Persistent Volumes           │ │
│  │ - /workspace (code)                 │ │
│  │ - /data (datasets)                  │ │
│  │ - /outputs (models/logs)            │ │
│  │ - /cache (pip/huggingface)          │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
              │
    ┌─────────────────┐
    │   macOS/Zed     │
    │  SSH Client     │
    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster with GPU nodes (tested on CoreWeave)
- `kubectl` configured with cluster access
- Docker for building images
- SSH key pair (`~/.ssh/id_ed25519`)

### 1. Clone and Configure

```bash
git clone <this-repo>
cd devpod-demo
```

### 2. Edit Configuration

Edit `config.env` and set your container registry:

```bash
# Container Registry Settings
REGISTRY="ghcr.io"
ORG="your-github-org"  # <-- Change this to your GitHub org
IMAGE_NAME="devpod-demo"
IMAGE_TAG="latest"
```

### 3. Run Setup

```bash
chmod +x setup.sh generate-manifests.sh
./setup.sh
```

The setup script will:
- Load your configuration from `config.env`
- Generate manifests with your registry settings
- Verify prerequisites
- Create SSH key secret in Kubernetes
- Build the multi-arch PyTorch+SSH container image
- Deploy storage and development pod
- Provide connection details

### 4. Setup Port-Forwarding and SSH

Start port-forwarding:
```bash
./port-forward.sh start
```

Add to your `~/.ssh/config`:
```
Host ml-dev
  HostName localhost
  Port 2222
  User dev
  IdentityFile ~/.ssh/id_ed25519
```

Connect:
```bash
ssh ml-dev
```

### 5. Connect with Zed (macOS)

First ensure port-forwarding is running, then in Zed: File → Open… → **Remote via SSH** → `dev@ml-dev:/workspace`

### 6. Start Developing

Your persistent workspace is at `/workspace`. Code changes survive pod restarts.

```bash
# In the SSH session - test GPU functionality
cd /workspace
python hello_gpu.py
```

## 📁 Project Structure

```
devpod-demo/
├── README.md                    # This file
├── config.env                   # Single configuration file (edit this!)
├── setup.sh                     # Interactive setup script
├── generate-manifests.sh        # Generate manifests from config
├── port-forward.sh              # Port-forward helper for SSH access
├── quick-start.sh               # Quick deployment script
├── run-job.sh                   # Training job submission helper
├── docker/
│   ├── Dockerfile              # Minimal SSH + dev user setup (uses CoreWeave PyTorch base)
│   ├── start-dev.sh            # Container startup script

│   └── .dockerignore          # Keep builds clean
├── k8s/                        # Generated manifests (don't edit directly!)
│   ├── 01-storage.yaml         # PVCs for workspace/data/outputs/cache
│   ├── 02-dev-statefulset.yaml # Development StatefulSet with SSH + 1 GPU
│   └── 03-training-job.yaml    # Training job templates (1/8 GPU, CPU)
└── examples/
    ├── hello_gpu.py            # Simple GPU hello world test
    └── test_multigpu.py        # Multi-GPU DDP test
```

## 🔧 Manual Deployment (Alternative to setup.sh)

### 1. Configure Your Setup

Edit `config.env` with your registry/org settings:

```bash
# Change these values
REGISTRY="ghcr.io"
ORG="your-github-org"
IMAGE_NAME="devpod-demo"
```

### 2. Generate Manifests

```bash
./generate-manifests.sh --all
```

This creates all K8s manifests with your configuration and proper GPU node scheduling.

### 3. Create SSH Key Secret

```bash
kubectl create namespace ml  # or whatever you set in config.env
kubectl create secret generic ml-dev-ssh-keys \
  --from-file=authorized_keys=~/.ssh/id_ed25519.pub \
  -n ml
```

### 4. Build Container Image

The container uses CoreWeave's PyTorch image as base with PyTorch 2.8.0 + CUDA 12.9 support. The setup script handles multi-platform builds automatically. For manual builds:

```bash
cd docker/
# Multi-platform build for both ARM64 and AMD64
docker buildx build --platform linux/amd64,linux/arm64 --push -t ghcr.io/your-org/devpod-demo:latest .
```

### 5. Deploy Resources

```bash
kubectl apply -f k8s/01-storage.yaml
kubectl apply -f k8s/02-dev-statefulset.yaml
```

### 6. Connect via Port-Forward

Start port-forwarding and connect:

```bash
# Start port-forwarding (runs in background)
./port-forward.sh start

# Connect via SSH
ssh dev@localhost -p 2222
```

## 🏃‍♂️ Testing GPU Functionality

### Quick GPU Tests

```bash
# Test GPU functionality in dev pod
ssh ml-dev
cd /workspace
python hello_gpu.py
```

### View Test Results

```bash
# Or submit training jobs using run-job.sh
./run-job.sh --help
```

## 🏃‍♂️ Running Training Jobs

### Submit Single GPU Job

```bash
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: custom-training
  namespace: ml
spec:
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        node.coreweave.cloud/class: gpu
      containers:
      - name: trainer
        image: ghcr.io/your-org/devpod-demo:latest
        command: ["python", "/workspace/my_training_script.py"]
        args: ["--epochs", "10", "--batch-size", "32"]
        resources:
          requests:
            nvidia.com/gpu: 1
          limits:
            nvidia.com/gpu: 1
        volumeMounts:
        - {name: workspace, mountPath: /workspace}
        - {name: datasets, mountPath: /data}
        - {name: outputs, mountPath: /outputs}
      volumes:
      - {name: workspace, persistentVolumeClaim: {claimName: ml-workspace}}
      - {name: datasets, persistentVolumeClaim: {claimName: ml-datasets}}
      - {name: outputs, persistentVolumeClaim: {claimName: ml-outputs}}
EOF
```

### Submit 8-GPU Distributed Job

```bash
# Edit and apply the 8-GPU job template
kubectl apply -f k8s/03-training-job.yaml
```

### Monitor Jobs

```bash
# List jobs
kubectl get jobs -n ml

# Watch job logs
kubectl logs -f job/pytorch-train-8gpu -n ml

# Get pod details
kubectl get pods -n ml -l job-name=pytorch-train-8gpu

# Or use the job runner
./run-job.sh logs pytorch-train-8gpu
```

## 🔧 Multi-Architecture Support

This project supports both AMD64 and ARM64 architectures:

### Supported Platforms
- **AMD64 (x86_64)**: Traditional GPU servers
- **ARM64 (aarch64)**: Grace Hopper and other ARM-based GPU nodes

### Key Features
- **Automatic Architecture Detection**: The setup script detects your host architecture
- **Multi-Platform Base Image**: Uses NVIDIA's multi-arch PyTorch containers
- **Smart Scheduling**: Automatically schedules on GPU nodes using `node.coreweave.cloud/class: gpu`
- **Cross-Architecture Development**: Develop on Apple Silicon, deploy to any GPU architecture

### Base Image
We use `nvcr.io/nvidia/pytorch:24.10-py3` which provides:
- ✅ Multi-architecture support (AMD64 + ARM64)
- ✅ CUDA 12.6 support
- ✅ PyTorch 2.5 with GPU acceleration
- ✅ Pre-optimized for NVIDIA GPUs

## 🐛 Troubleshooting

### Architecture Issues

```bash
# Check node architecture and GPU availability
kubectl get nodes -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,GPU:.status.capacity.nvidia\.com/gpu

# Verify pod is on correct architecture
kubectl exec -n ml ml-dev-0 -- uname -m

# Check if container matches node architecture
kubectl describe pod ml-dev-0 -n ml | grep "Node:\|Image:"
```

### SSH Connection Issues

```bash
# Check port-forward status
./port-forward.sh status

# Restart port-forward
./port-forward.sh restart

# Check dev pod status
kubectl get pods -n ml -l app=ml-dev

# Get pod logs
kubectl logs -n ml ml-dev-0

# Manual port-forward if needed
kubectl port-forward -n ml svc/ml-dev 2222:22 8888:8888 6006:6006
```

### GPU Issues

```bash
# Check GPU visibility in dev pod
kubectl exec -n ml ml-dev-0 -- nvidia-smi

# Check CUDA availability in Python
kubectl exec -n ml ml-dev-0 -- python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, Devices: {torch.cuda.device_count()}')"

# Check GPU allocation on nodes
kubectl describe nodes | grep -A 5 -B 5 nvidia.com/gpu
```

### Container Issues

```bash
# Check for exec format errors
kubectl logs -n ml ml-dev-0

# Verify image architecture
docker buildx imagetools inspect ghcr.io/your-org/devpod-demo:latest

# Pull and test image locally
docker run --rm ghcr.io/your-org/devpod-demo:latest uname -m
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n ml

# Check available storage
kubectl exec -n ml ml-dev-0 -- df -h
```

## 🎛️ Customization

### GPU Node Scheduling
The project automatically schedules pods on GPU nodes using:
```yaml
nodeSelector:
  node.coreweave.cloud/class: gpu
```

For other clusters, edit `generate-manifests.sh` to change the nodeSelector.

### Adjust GPU Allocation

Edit `config.env`:
```bash
DEFAULT_DEV_GPU_LIMIT="2"  # Change from 1 to 2 GPUs
```

Then regenerate manifests:
```bash
./generate-manifests.sh --all
kubectl apply -f k8s/02-dev-statefulset.yaml
```

### Add Python Packages

The CoreWeave PyTorch base image includes most ML packages you'll need (PyTorch, transformers, etc.). For additional packages, install them directly in the dev pod:

```bash
# SSH into dev pod
ssh ml-dev

# Install packages (they persist in your workspace)
pip install --user package-name

# Or install globally if needed
sudo pip install package-name
```

If you need packages in the base image, modify the Dockerfile and rebuild:
```bash
# Use setup.sh for interactive rebuild
./setup.sh  # Select option 3: Build and update image only

# Restart pod with new image
kubectl rollout restart statefulset/ml-dev -n ml
```

### Change Storage Sizes

Edit `config.env`:
```bash
WORKSPACE_SIZE="100Gi"   # Increase workspace
DATASETS_SIZE="1Ti"      # Increase dataset storage
```

Regenerate and apply:
```bash
./generate-manifests.sh --all
kubectl apply -f k8s/01-storage.yaml
```

## 🔐 Security Considerations

- SSH access is key-based only (no passwords)
- Pods are scheduled only on GPU nodes with proper resource limits
- Uses namespace isolation (`ml` namespace)
- Private container registry recommended for production
- SSH keys are stored as Kubernetes secrets
- Consider NetworkPolicy to restrict SSH access by IP

## 📊 Resource Requirements

### Minimum Requirements
- **CPU**: 2 cores per dev pod
- **Memory**: 8Gi per dev pod
- **GPU**: 1x NVIDIA GPU per dev pod
- **Storage**: 50Gi workspace + 500Gi datasets + 200Gi outputs + 100Gi cache

### Recommended for Production
- **CPU**: 4-8 cores per dev pod
- **Memory**: 16-32Gi per dev pod
- **GPU**: 1-2x GPUs per dev pod
- **Storage**: Larger PVCs based on dataset size

## 📚 Next Steps

### Quick Start Checklist
- [ ] Run `./setup.sh` with your registry settings
- [ ] SSH into dev pod and test GPU: `ssh ml-dev`, then `python /workspace/hello_gpu.py`
- [ ] Start developing: your code in `/workspace` persists across pod restarts
- [ ] Create your own training scripts in `/workspace`

---

**Happy coding!** 🚀 This setup gives you a robust, persistent, multi-architecture ML development environment on Kubernetes that scales from experimentation to production training.