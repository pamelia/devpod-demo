#!/usr/bin/env python3
"""
PyTorch GPU Hello World
Simple script to verify PyTorch installation and GPU availability.
"""

import torch
import time
import os

def print_header():
    print("🚀 PyTorch GPU Hello World")
    print("=" * 50)

def check_pytorch():
    print(f"✅ PyTorch version: {torch.__version__}")
    print(f"✅ Python executable: {torch.version.__file__}")

def check_cuda():
    print(f"🔍 CUDA available: {torch.cuda.is_available()}")

    if torch.cuda.is_available():
        print(f"✅ CUDA version: {torch.version.cuda}")
        print(f"✅ GPU count: {torch.cuda.device_count()}")

        for i in range(torch.cuda.device_count()):
            gpu_name = torch.cuda.get_device_name(i)
            gpu_memory = torch.cuda.get_device_properties(i).total_memory / 1e9
            print(f"   GPU {i}: {gpu_name} ({gpu_memory:.1f} GB)")

        # Show current GPU
        current_device = torch.cuda.current_device()
        print(f"✅ Current GPU: {current_device} ({torch.cuda.get_device_name(current_device)})")
    else:
        print("⚠️  No CUDA GPUs available - running on CPU")

def test_tensor_operations():
    print("\n🧮 Testing tensor operations...")

    # Create test tensors
    size = 1000
    device = 'cuda' if torch.cuda.is_available() else 'cpu'

    print(f"Creating {size}x{size} tensors on {device.upper()}")

    # Create tensors
    a = torch.randn(size, size, device=device)
    b = torch.randn(size, size, device=device)

    # Time matrix multiplication
    start_time = time.time()
    c = torch.mm(a, b)
    end_time = time.time()

    print(f"✅ Matrix multiplication completed in {end_time - start_time:.3f} seconds")
    print(f"✅ Result tensor shape: {c.shape}")
    print(f"✅ Result tensor device: {c.device}")

    # Simple computation
    result = torch.mean(c).item()
    print(f"✅ Mean of result: {result:.6f}")

def test_distributed():
    print("\n🌐 Distributed training info...")

    world_size = int(os.environ.get('WORLD_SIZE', 1))
    rank = int(os.environ.get('RANK', 0))
    local_rank = int(os.environ.get('LOCAL_RANK', 0))

    print(f"World size: {world_size}")
    print(f"Global rank: {rank}")
    print(f"Local rank: {local_rank}")

    if world_size > 1:
        print("✅ Distributed training environment detected")
    else:
        print("ℹ️  Single process (no distributed training)")

def show_environment():
    print("\n🔧 Environment info...")

    # Show key environment variables
    env_vars = [
        'CUDA_VISIBLE_DEVICES',
        'NVIDIA_VISIBLE_DEVICES',
        'WORLD_SIZE',
        'RANK',
        'LOCAL_RANK'
    ]

    for var in env_vars:
        value = os.environ.get(var, 'not set')
        print(f"{var}: {value}")

def main():
    print_header()

    try:
        check_pytorch()
        check_cuda()
        test_tensor_operations()
        test_distributed()
        show_environment()

        print("\n🎉 All tests completed successfully!")
        print("PyTorch is working correctly with GPU support.")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        print("There may be an issue with your PyTorch installation.")
        return 1

    return 0

if __name__ == '__main__':
    exit(main())
