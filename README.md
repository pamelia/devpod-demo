# DevPod on Kubernetes for ML Development

This project demonstrates how to use **DevPod inside a Kubernetes cluster** for PyTorch machine learning development, providing a persistent development environment that doesn't require rebuilding containers for code changes.

## 🎯 What This Solves

- **Persistent Development**: Your code lives in persistent storage, not in the container
- **Remote Development**: SSH access for tools like Zed, VS Code Remote, or terminal
- **GPU Access**: Full access to node GPUs for both interactive development and training jobs
- **No Container Rebuilds**: Iterate on code without rebuilding/pushing containers
- **Shared Resources**: Same data and output volumes across dev environment and training jobs

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│ Kubernetes Single Node (8x GPUs)       │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────┐  ┌───────────────┐ │
│  │   Dev Pod       │  │ Training Jobs │ │
│  │ - SSH Server    │  │ - 1, 4, 8 GPU │ │
│  │ - PyTorch+CUDA  │  │ - Batch Jobs  │ │
│  │ - 1 GPU         │  │ - Same PVCs   │ │
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

- Kubernetes cluster (single node with GPUs)
- `kubectl` configured 
- Docker for building images
- SSH key pair (`~/.ssh/id_ed25519`)

### 1. Clone and Configure

```bash
git clone <this-repo>
cd devpod-demo
```

### 2. Edit Configuration

Edit `config.env` and set your GitHub organization:

```bash
# Container Registry Settings
REGISTRY="ghcr.io"
ORG="your-github-org"  # <-- Change this to your GitHub org
IMAGE_NAME="pytorch-dev"
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
- Build the PyTorch+SSH container image
- Deploy storage and development pod
- Provide connection details

### 2. Setup Port-Forwarding and SSH

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

### 3. Connect with Zed (macOS)

First ensure port-forwarding is running, then in Zed: File → Open… → **Remote via SSH** → `dev@ml-dev:/workspace`

### 4. Start Developing

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
├── setup.sh                     # Automated setup script
├── run-job.sh                   # Easy training job submission
├── generate-manifests.sh        # Generate manifests from config
├── port-forward.sh              # Port-forward helper for SSH access
├── build-multiplatform.sh       # Multi-platform Docker builds
├── test-gpu.sh                  # Simple GPU test runner
├── docker/
│   ├── Dockerfile              # PyTorch + SSH development image
│   ├── start-dev.sh            # Container startup script
│   ├── requirements.txt        # Python dependencies
│   ├── Makefile               # Docker build helpers
│   └── .dockerignore          # Keep builds clean
├── k8s/                        # Generated manifests (don't edit directly)
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
IMAGE_NAME="pytorch-dev"
```

### 2. Generate Manifests

```bash
./generate-manifests.sh --all
```

This creates all K8s manifests with your configuration.

### 3. Create SSH Key Secret

```bash
kubectl create namespace ml  # or whatever you set in config.env
kubectl create secret generic ml-dev-ssh-keys \
  --from-file=authorized_keys=~/.ssh/id_ed25519.pub \
  -n ml
```

### 4. Build Container Image

For multi-platform builds (recommended):
```bash
# Build for both AMD64 and ARM64
./build-multiplatform.sh push

# Or build specific platforms
./build-multiplatform.sh --platforms linux/amd64 push
```

For single-platform builds:
```bash
cd docker/
make build-push REGISTRY=ghcr.io ORG=your-org IMAGE_NAME=pytorch-dev
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
# Test single GPU
./test-gpu.sh hello

# Test all 8 GPUs with distributed training
./test-gpu.sh multigpu

# Test CPU-only mode
./test-gpu.sh cpu

# Run test interactively in dev pod
./test-gpu.sh interactive
```

### View Test Results

```bash
# List test jobs
./test-gpu.sh list

# Show logs
./test-gpu.sh logs hello-gpu

# Clean up test jobs
./test-gpu.sh cleanup
```

## 🏃‍♂️ Running Training Jobs (Advanced)

### Submit Single GPU Job

```bash
kubectl apply -f - <<EOF
# For custom training jobs, create your own training script
apiVersion: batch/v1
kind: Job
metadata:
  name: custom-training
  namespace: ml
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: trainer
        image: your-registry/pytorch-dev:latest
        command: ["python", "/workspace/my_training_script.py"]
        args: ["--epochs", "10", "--batch-size", "32"]
        resources:
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

## 🐛 Troubleshooting

### SSH Connection Issues

```bash
# Check port-forward status
./port-forward.sh status

# Restart port-forward
./port-forward.sh restart

# Check dev pod status
kubectl get pods -n ml -l app=ml-dev

# Get pod logs
kubectl logs -n ml deployment/ml-dev

# Manual port-forward if needed
kubectl port-forward -n ml svc/ml-dev 2222:22 8888:8888 6006:6006
```

### GPU Issues

```bash
# Check GPU visibility in dev pod
kubectl exec -n ml deployment/ml-dev -- nvidia-smi

# Check GPU allocation
kubectl describe node <node-name> | grep nvidia.com/gpu
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n ml

# Check available storage
kubectl exec -n ml deployment/ml-dev -- df -h
```

### Training Job Issues

```bash
# Check job status
kubectl describe job/<job-name> -n ml

# Get job logs
kubectl logs job/<job-name> -n ml

# Check events
kubectl get events -n ml --sort-by='.lastTimestamp'
```

## 🎛️ Customization

### Adjust GPU Allocation

Edit `k8s/02-dev-statefulset.yaml`:
```yaml
resources:
  limits:
    nvidia.com/gpu: 2  # Change from 1 to 2 GPUs
```

### Add Python Packages

Edit `docker/requirements.txt` and rebuild:
```bash
# Multi-platform build (recommended)
./build-multiplatform.sh push

# Or single platform
cd docker/
make build-push  # Uses config.env settings automatically

kubectl rollout restart deployment/ml-dev -n ml
```

### Change Storage Sizes

Edit `k8s/01-storage.yaml`:
```yaml
resources:
  requests:
    storage: 1Ti  # Increase from 500Gi
```

## 🔐 Security Considerations

- SSH access is key-based only (no passwords)
- Consider NetworkPolicy to restrict SSH access by IP
- Use private container registries for production
- Regularly rotate SSH keys
- Monitor resource usage and set appropriate limits
- **Important**: Update `config.env` with your actual registry details before deploying

## 🚀 Production Considerations

- Use Helm charts for easier management
- Implement backup strategies for PVCs
- Set up monitoring (Prometheus/Grafana)
- Configure log aggregation
- Use RBAC for proper access control
- Consider using a service mesh for network policies
- Use ingress controllers instead of port-forward for permanent access
- Set up VPN or bastion host for secure remote access

## 🏗️ Multi-Platform Builds

This project supports building Docker images for multiple architectures:

### Quick Commands

```bash
# Build and push multi-platform (AMD64 + ARM64)
./build-multiplatform.sh push

# Build for AMD64 only (most GPU nodes)
./build-multiplatform.sh --platforms linux/amd64 push

# Build for local development
./build-multiplatform.sh build-local

# Inspect built image platforms
./build-multiplatform.sh inspect
```

### Why Multi-Platform?

- **Development on Apple Silicon** (ARM64) while deploying to **x86_64 GPU nodes**
- **Flexibility** to run on different cluster architectures
- **Future-proofing** for ARM-based GPU instances

### Platform Support

- `linux/amd64` - Most GPU nodes (NVIDIA, Intel)
- `linux/arm64` - ARM-based nodes, Apple Silicon development

## 📚 Next Steps

### Quick Start Checklist
- [ ] Run `./test-gpu.sh hello` to verify single GPU works
- [ ] Run `./test-gpu.sh multigpu` to test all 8 GPUs  
- [ ] SSH into dev pod and start developing: `ssh dev@ml-dev`
- [ ] Create your own training scripts in `/workspace`

### Advanced Setup
1. **Helm Chart**: Convert manifests to a Helm chart for easier management
2. **CI/CD Integration**: Automate multi-platform image builds and deployments
3. **Multi-Node**: Extend to multi-node distributed training
4. **Experiment Tracking**: Integrate with MLflow, Weights & Biases
5. **Data Pipeline**: Add data preprocessing and validation jobs

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

---

**Happy coding!** 🚀 This setup gives you a robust, persistent ML development environment on Kubernetes that scales from experimentation to production training.