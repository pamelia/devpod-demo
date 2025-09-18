#!/bin/bash
set -e

# Container startup script for ML development environment
# This script sets up SSH keys and starts the SSH daemon

echo "Starting ML development container..."

# Generate SSH host keys if they don't exist
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
fi

# Setup authorized_keys from secret mount if available
if [ -f /ssh-keys/authorized_keys ]; then
    echo "Setting up SSH authorized keys..."
    mkdir -p /home/dev/.ssh
    cp /ssh-keys/authorized_keys /home/dev/.ssh/authorized_keys
    chown -R dev:dev /home/dev/.ssh
    chmod 700 /home/dev/.ssh
    chmod 600 /home/dev/.ssh/authorized_keys
    echo "SSH keys configured for user 'dev'"
else
    echo "Warning: No SSH keys found at /ssh-keys/authorized_keys"
    echo "SSH access will not be available"
fi

# Ensure workspace directory has correct ownership
chown -R dev:dev /workspace 2>/dev/null || true

# Print some useful information
echo "=== Container Information ==="
echo "User: dev (uid: $(id -u dev))"
echo "Workspace: /workspace"
echo "Data: /data"
echo "Outputs: /outputs"
echo "Cache: /home/dev/.cache"

if command -v nvidia-smi &> /dev/null; then
    echo "GPUs available:"
    nvidia-smi -L 2>/dev/null || echo "  No GPUs detected"
else
    echo "NVIDIA tools not available (CPU-only mode)"
fi

if command -v python &> /dev/null; then
    echo "Python version: $(python --version)"
    echo "PyTorch version: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'Not installed')"
    echo "CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'Unknown')"
fi

echo "============================="

# Start SSH daemon
echo "Starting SSH daemon..."
exec /usr/sbin/sshd -D -e
