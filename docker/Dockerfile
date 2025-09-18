# PyTorch development container with SSH access for remote editing
# Use --platform flag to target specific architecture
ARG TARGETPLATFORM
ARG BUILDPLATFORM
FROM --platform=${TARGETPLATFORM:-linux/amd64} pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime

# Install system dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    git \
    curl \
    wget \
    vim \
    nano \
    htop \
    tmux \
    screen \
    ca-certificates \
    build-essential \
    rsync \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Create dev user and setup SSH
RUN mkdir -p /var/run/sshd /home/dev/.ssh && \
    useradd -m -s /bin/bash -u 1000 dev && \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev && \
    chown -R dev:dev /home/dev

# Install additional Python packages commonly used in ML
RUN pip install --no-cache-dir \
    torchvision \
    torchaudio \
    torchmetrics \
    transformers \
    datasets \
    accelerate \
    wandb \
    tensorboard \
    jupyter \
    jupyterlab \
    matplotlib \
    seaborn \
    pandas \
    numpy \
    scipy \
    scikit-learn \
    pillow \
    tqdm \
    pyyaml \
    click \
    rich

# Setup workspace directory
RUN mkdir -p /workspace && chown -R dev:dev /workspace

# SSH configuration - disable password auth, enable key auth
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

# Copy startup script
COPY start-dev.sh /usr/local/bin/start-dev.sh
RUN chmod +x /usr/local/bin/start-dev.sh

# Switch to dev user for shell setup
USER dev
WORKDIR /workspace

# Setup useful shell aliases and environment
RUN echo 'alias ll="ls -la"' >> ~/.bashrc && \
    echo 'alias la="ls -A"' >> ~/.bashrc && \
    echo 'alias l="ls -CF"' >> ~/.bashrc && \
    echo 'export PYTHONPATH=/workspace:$PYTHONPATH' >> ~/.bashrc && \
    echo 'export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-all}' >> ~/.bashrc && \
    echo 'cd /workspace' >> ~/.bashrc

# Back to root for startup
USER root

EXPOSE 22

CMD ["/usr/local/bin/start-dev.sh"]
