#!/usr/bin/env python3
"""
Multi-GPU Test Script
Simple test to verify multi-GPU functionality with PyTorch DDP.
"""

import os
import torch
import torch.distributed as dist
from torch.multiprocessing.spawn import spawn  # type: ignore
from torch.nn.parallel import DistributedDataParallel as DDP
import time
from typing import cast

def setup_distributed(rank: int, world_size: int) -> None:
    """Initialize distributed training."""
    os.environ['MASTER_ADDR'] = 'localhost'
    os.environ['MASTER_PORT'] = '12355'

    # Initialize process group
    dist.init_process_group("nccl", rank=rank, world_size=world_size)

    # Set device
    torch.cuda.set_device(rank)

def cleanup_distributed() -> None:
    """Clean up distributed training."""
    dist.destroy_process_group()

def run_gpu_test(rank: int, world_size: int) -> None:
    """Run GPU test on specific rank."""
    setup_distributed(rank, world_size)

    device: int = torch.cuda.current_device()
    gpu_name: str = torch.cuda.get_device_name(device)

    print(f"[Rank {rank}] Running on GPU {device}: {gpu_name}")

    # Create test tensors
    size: int = 2000
    a: torch.Tensor = torch.randn(size, size, device=device)
    b: torch.Tensor = torch.randn(size, size, device=device)

    # Time computation
    start_time: float = time.time()
    for _ in range(5):
        _ = torch.mm(a, b)  # Assign to _ to indicate intentional unused result
        torch.cuda.synchronize()  # Wait for computation to complete
    end_time: float = time.time()

    avg_time: float = (end_time - start_time) / 5

    print(f"[Rank {rank}] Matrix multiplication avg time: {avg_time:.3f}s")

    # Test all-reduce operation
    test_tensor: torch.Tensor = torch.ones(10, device=device) * rank
    before_list = cast('list[float]', test_tensor[:3].tolist())  # type: ignore
    print(f"[Rank {rank}] Before all-reduce: {before_list}")

    _ = dist.all_reduce(test_tensor, op=dist.ReduceOp.SUM)  # type: ignore

    after_list = cast('list[float]', test_tensor[:3].tolist())  # type: ignore
    print(f"[Rank {rank}] After all-reduce: {after_list}")

    # Simple DDP test
    model: torch.nn.Linear = torch.nn.Linear(100, 10).to(device)
    ddp_model: DDP = DDP(model, device_ids=[rank])

    # Test forward pass
    input_tensor: torch.Tensor = torch.randn(32, 100, device=device)
    output: torch.Tensor = cast(torch.Tensor, ddp_model(input_tensor))

    print(f"[Rank {rank}] DDP model output shape: {output.shape}")

    cleanup_distributed()
    print(f"[Rank {rank}] Test completed successfully! ✅")

def main() -> int:
    print("🚀 Multi-GPU Test Starting")
    print("=" * 40)

    if not torch.cuda.is_available():
        print("❌ CUDA not available - cannot test multi-GPU")
        return 1

    gpu_count: int = torch.cuda.device_count()
    print(f"Available GPUs: {gpu_count}")

    if gpu_count < 2:
        print("⚠️  Only 1 GPU available - testing single GPU instead")
        run_gpu_test(0, 1)
        return 0

    print(f"Testing with {gpu_count} GPUs")

    # Show GPU info
    for i in range(gpu_count):
        name: str = torch.cuda.get_device_name(i)
        device_props = torch.cuda.get_device_properties(i)  # type: ignore
        memory: float = cast(int, device_props.total_memory) / 1e9
        print(f"  GPU {i}: {name} ({memory:.1f} GB)")

    print("\nStarting distributed test...")

    # Run multi-process test
    _ = spawn(run_gpu_test, args=(gpu_count,), nprocs=gpu_count, join=True)  # type: ignore

    print("\n🎉 Multi-GPU test completed successfully!")
    return 0

if __name__ == '__main__':
    exit(main())
