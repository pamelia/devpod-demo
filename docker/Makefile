# Makefile for PyTorch Development Container
# Simplifies Docker build, push, and management operations

# Configuration
IMAGE_NAME ?= pytorch-dev
IMAGE_TAG ?= latest
REGISTRY ?=
FULL_IMAGE = $(if $(REGISTRY),$(REGISTRY)/,)$(IMAGE_NAME):$(IMAGE_TAG)

# Default target
.PHONY: help
help:
	@echo "PyTorch Development Container - Docker Operations"
	@echo ""
	@echo "Usage:"
	@echo "  make build                    Build the Docker image"
	@echo "  make push                     Push image to registry"
	@echo "  make build-push               Build and push in one command"
	@echo "  make run                      Run container locally for testing"
	@echo "  make shell                    Get shell in running container"
	@echo "  make clean                    Remove local image"
	@echo "  make logs                     Show logs from running container"
	@echo ""
	@echo "Configuration:"
	@echo "  IMAGE_NAME=$(IMAGE_NAME)"
	@echo "  IMAGE_TAG=$(IMAGE_TAG)"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  FULL_IMAGE=$(FULL_IMAGE)"
	@echo ""
	@echo "Examples:"
	@echo "  make build IMAGE_NAME=my-pytorch-dev"
	@echo "  make push REGISTRY=ghcr.io/myorg IMAGE_TAG=v1.0.0"
	@echo "  make build-push REGISTRY=docker.io/myuser IMAGE_NAME=pytorch-ml"

.PHONY: build
build:
	@echo "Building Docker image: $(FULL_IMAGE)"
	docker build --platform linux/amd64,linux/arm64 -t $(FULL_IMAGE) .
	@echo "✅ Build completed: $(FULL_IMAGE)"

.PHONY: push
push:
	@echo "Pushing Docker image: $(FULL_IMAGE)"
	docker buildx build --platform linux/amd64,linux/arm64 --push -t $(FULL_IMAGE) .
	@echo "✅ Push completed: $(FULL_IMAGE)"

.PHONY: build-push
build-push:
	@echo "Building and pushing multi-platform image: $(FULL_IMAGE)"
	docker buildx build --platform linux/amd64,linux/arm64 --push -t $(FULL_IMAGE) .
	@echo "✅ Build and push completed: $(FULL_IMAGE)"

.PHONY: run
run:
	@echo "Running container locally: $(FULL_IMAGE)"
	@echo "Access via: ssh dev@localhost -p 2222 (after container starts)"
	docker run -d \
		--name pytorch-dev-test \
		--rm \
		-p 2222:22 \
		-p 8888:8888 \
		-p 6006:6006 \
		--gpus all \
		-v $(PWD)/test-workspace:/workspace \
		-v $(PWD)/test-data:/data \
		-v $(PWD)/test-outputs:/outputs \
		$(FULL_IMAGE)
	@echo "✅ Container started. Use 'make logs' to see startup progress"
	@echo "🔑 Note: No SSH keys mounted - container will warn about missing keys"

.PHONY: shell
shell:
	@echo "Getting shell in container..."
	docker exec -it pytorch-dev-test /bin/bash

.PHONY: stop
stop:
	@echo "Stopping test container..."
	-docker stop pytorch-dev-test
	@echo "✅ Container stopped"

.PHONY: logs
logs:
	@echo "Showing container logs..."
	docker logs -f pytorch-dev-test

.PHONY: clean
clean:
	@echo "Cleaning up local image: $(FULL_IMAGE)"
	-docker rmi $(FULL_IMAGE)
	@echo "✅ Local image removed"

.PHONY: clean-all
clean-all: stop clean
	@echo "Cleaning up test directories..."
	-rm -rf test-workspace test-data test-outputs
	@echo "✅ All cleaned up"

# Development helpers
.PHONY: test-dirs
test-dirs:
	@echo "Creating test directories for local development..."
	mkdir -p test-workspace test-data test-outputs
	echo "print('Hello from test workspace!')" > test-workspace/hello.py
	echo "# Test workspace created" > test-workspace/README.md
	@echo "✅ Test directories created"

.PHONY: quick-test
quick-test: test-dirs build run
	@echo "Quick test setup completed!"
	@echo "Wait a few seconds, then try: ssh dev@localhost -p 2222"
	@echo "Or get logs with: make logs"

# Show current configuration
.PHONY: config
config:
	@echo "Current Configuration:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  REGISTRY: $(if $(REGISTRY),$(REGISTRY),<none - local only>)"
	@echo "  FULL_IMAGE: $(FULL_IMAGE)"
	@echo ""
	@echo "Docker info:"
	@docker --version 2>/dev/null || echo "  Docker: not available"
	@echo "  Buildx available: $$(docker buildx version 2>/dev/null && echo "yes" || echo "no")"
	@echo -n "  Images: "
	@docker images $(IMAGE_NAME) --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null | tail -n +2 | wc -l | tr -d ' '
	@echo " local image(s) found"

# Show build context size
.PHONY: context-size
context-size:
	@echo "Docker build context size:"
	@tar --exclude-vcs -czf - . | wc -c | numfmt --to=iec-i --suffix=B

.PHONY: inspect
inspect:
	@echo "Inspecting image: $(FULL_IMAGE)"
	docker inspect $(FULL_IMAGE) | jq '.[0] | {Id: .Id, Created: .Created, Size: .Size, Architecture: .Architecture, Os: .Os}'
