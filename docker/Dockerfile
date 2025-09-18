# PyTorch development container with SSH access for remote editing
FROM ghcr.io/coreweave/ml-containers/torch:es-ubuntu-24-dev-2dd65d0-base-cuda12.9.1-ubuntu24.04-torch2.8.0-vision0.23.0-audio2.8.0-abi1

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

# Create dev user and setup SSH (use next available UID)
RUN mkdir -p /var/run/sshd /home/dev/.ssh && \
    useradd -m -s /bin/bash dev && \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev && \
    chown -R dev:dev /home/dev

# Skip Python package installation - CoreWeave image has everything we need

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
