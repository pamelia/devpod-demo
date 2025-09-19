#!/usr/bin/env python3
"""
🚀 GPU Performance Demo - Robust Matrix Computing Showcase
A comprehensive demonstration of GPU-accelerated computing with PyTorch
that showcases the raw computational power of modern GPUs.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import time
from typing import Callable, override

class GPUPerformanceDemo:
    def __init__(self) -> None:
        self.device: torch.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.gpu_available: bool = torch.cuda.is_available()

        if self.gpu_available:
            torch.backends.cudnn.benchmark = True
            print("🔥 GPU mode activated!")
        else:
            print("⚠️  Running on CPU")

    def show_gpu_specs(self) -> None:
        """Display GPU specifications"""
        print("🎯 GPU PERFORMANCE SHOWCASE")
        print("=" * 60)

        if self.gpu_available:
            for i in range(torch.cuda.device_count()):
                name = torch.cuda.get_device_name(i)
                props = torch.cuda.get_device_properties(i)
                memory_gb = props.total_memory / (1024**3)

                print(f"🚀 GPU {i}: {name}")
                print(f"   💾 Memory: {memory_gb:.1f} GB")
                print(f"   🔧 Compute: {props.major}.{props.minor}")
                print(f"   ⚡ Multiprocessors: {props.multi_processor_count}")

                # Check current memory usage
                allocated = torch.cuda.memory_allocated(i) / (1024**3)
                cached = torch.cuda.memory_reserved(i) / (1024**3)
                print(f"   📊 Memory Used: {allocated:.2f} GB / {cached:.2f} GB cached")

        print(f"🐍 PyTorch: {torch.__version__}")
        print()

    def benchmark_matrix_sizes(self) -> None:
        """Benchmark matrix multiplication across different sizes"""
        print("🔥 MATRIX MULTIPLICATION BENCHMARK")
        print("-" * 50)

        # Adjust sizes based on available memory
        if self.gpu_available:
            sizes = [1000, 2000, 4000, 6000, 8000]
        else:
            sizes = [500, 1000, 2000]

        results: list[tuple[int, float, float]] = []

        for size in sizes:
            print(f"📊 Testing {size}x{size} matrices...")

            # Create matrices
            A = torch.randn(size, size, device=self.device, dtype=torch.float32)
            B = torch.randn(size, size, device=self.device, dtype=torch.float32)

            # Warm up
            _ = torch.mm(A, B)
            if self.gpu_available:
                torch.cuda.synchronize()

            # Benchmark
            num_runs = 5
            times: list[float] = []

            for _ in range(num_runs):
                start = time.time()
                _ = torch.mm(A, B)
                if self.gpu_available:
                    torch.cuda.synchronize()
                times.append(time.time() - start)

            avg_time = sum(times) / len(times)

            # Calculate FLOPS (2*n^3 operations for matrix multiplication)
            flops = 2.0 * size**3
            tflops = flops / avg_time / 1e12

            print(f"   ⏱️  Time: {avg_time:.4f}s")
            print(f"   ⚡ Performance: {tflops:.2f} TFLOPS")

            results.append((size, avg_time, tflops))

            # Clean up
            del A, B
            if self.gpu_available:
                torch.cuda.empty_cache()

        # Show summary
        print("\n📈 PERFORMANCE SUMMARY:")
        for size, time_taken, tflops in results:
            print(f"   {size:4d}x{size:<4d}: {tflops:6.2f} TFLOPS ({time_taken:.4f}s)")

        print()

    def neural_network_training_demo(self) -> None:
        """Demonstrate neural network training performance"""
        print("🧠 NEURAL NETWORK TRAINING DEMO")
        print("-" * 50)

        # Create a deep network
        class DeepNet(nn.Module):
            def __init__(self, input_dim: int = 1024) -> None:
                super().__init__()
                self.layers: nn.Sequential = nn.Sequential(
                    nn.Linear(input_dim, 2048),
                    nn.ReLU(),
                    nn.BatchNorm1d(2048),
                    nn.Dropout(0.2),

                    nn.Linear(2048, 1024),
                    nn.ReLU(),
                    nn.BatchNorm1d(1024),
                    nn.Dropout(0.2),

                    nn.Linear(1024, 512),
                    nn.ReLU(),
                    nn.BatchNorm1d(512),
                    nn.Dropout(0.1),

                    nn.Linear(512, 256),
                    nn.ReLU(),
                    nn.BatchNorm1d(256),

                    nn.Linear(256, 10)
                )

            @override
            def forward(self, x: torch.Tensor) -> torch.Tensor:
                return self.layers(x)

        # Setup
        batch_size = 512 if self.gpu_available else 64
        input_dim = 1024
        num_epochs = 10

        model = DeepNet(input_dim).to(self.device)
        optimizer = torch.optim.AdamW(model.parameters(), lr=0.001)
        criterion = nn.CrossEntropyLoss()

        # Count parameters
        total_params = sum(p.numel() for p in model.parameters())
        print(f"📊 Model parameters: {total_params:,}")
        print(f"📊 Batch size: {batch_size}")

        # Generate synthetic data
        num_samples = batch_size * 100
        X = torch.randn(num_samples, input_dim, device=self.device)
        y = torch.randint(0, 10, (num_samples,), device=self.device)

        # Training loop
        model.train()
        start_time = time.time()

        for epoch in range(num_epochs):
            epoch_loss = 0.0
            num_batches = 0

            # Mini-batch training
            for i in range(0, len(X), batch_size):
                batch_X = X[i:i+batch_size]
                batch_y = y[i:i+batch_size]

                optimizer.zero_grad()
                outputs = model(batch_X)
                loss = criterion(outputs, batch_y)
                loss.backward()
                _ = optimizer.step()

                epoch_loss += loss.item()
                num_batches += 1

            if epoch % 2 == 0:
                avg_loss = epoch_loss / num_batches
                print(f"   Epoch {epoch+1:2d}: Loss = {avg_loss:.6f}")

        training_time = time.time() - start_time

        # Calculate throughput
        total_samples = len(X) * num_epochs
        samples_per_second = total_samples / training_time

        print(f"✅ Training completed in {training_time:.2f}s")
        print(f"⚡ Throughput: {samples_per_second:.0f} samples/second")
        print()

    def advanced_tensor_operations(self) -> None:
        """Showcase advanced tensor operations"""
        print("⚡ ADVANCED TENSOR OPERATIONS")
        print("-" * 50)

        size = 10000 if self.gpu_available else 5000

        print(f"📊 Working with {size:,} element tensors")

        # Create test data
        x = torch.randn(size, device=self.device)
        y = torch.randn(size, device=self.device)

        operations: list[tuple[str, Callable[[], torch.Tensor]]] = [
            ("Element-wise multiply", lambda: x * y),
            ("Sine + Cosine", lambda: torch.sin(x) + torch.cos(y)),
            ("Exponential", lambda: torch.exp(torch.clamp(x, -5, 5))),
            ("Square root", lambda: torch.sqrt(torch.abs(x) + 1e-8)),
            ("Logarithm", lambda: torch.log(torch.abs(x) + 1e-8)),
            ("Power operation", lambda: torch.pow(torch.abs(x) + 1e-8, 0.5)),
            ("Hyperbolic tangent", lambda: torch.tanh(x)),
            ("Softmax", lambda: F.softmax(x.view(1, -1), dim=1)),
        ]

        for op_name, op_func in operations:
            # Warm up
            _ = op_func()
            if self.gpu_available:
                torch.cuda.synchronize()

            # Benchmark
            start = time.time()
            _ = op_func()
            if self.gpu_available:
                torch.cuda.synchronize()
            op_time = time.time() - start

            print(f"   {op_name:20}: {op_time:.6f}s")

        print()

    def memory_throughput_test(self) -> None:
        """Test GPU memory bandwidth"""
        if not self.gpu_available:
            return

        print("💾 MEMORY BANDWIDTH TEST")
        print("-" * 50)

        # Test different memory sizes
        test_sizes: list[tuple[int, str]] = [
            (100, "100 MB"),
            (500, "500 MB"),
            (1000, "1 GB"),
            (2000, "2 GB")
        ]

        for size_mb, size_desc in test_sizes:
            elements = size_mb * 1024 * 1024 // 4  # 4 bytes per float32

            print(f"📊 Testing {size_desc} ({elements:,} elements)")

            # Allocate tensors
            source = torch.randn(elements, device=self.device, dtype=torch.float32)

            # Memory copy test
            start = time.time()
            destination = source.clone()
            torch.cuda.synchronize()
            copy_time = time.time() - start

            # Calculate bandwidth (read + write = 2x data movement)
            bytes_moved = elements * 4 * 2  # float32 = 4 bytes, read+write
            bandwidth_gb_s = bytes_moved / copy_time / (1024**3)

            print(f"   ⏱️  Copy time: {copy_time:.4f}s")
            print(f"   ⚡ Bandwidth: {bandwidth_gb_s:.1f} GB/s")

            # Clean up
            del source, destination
            torch.cuda.empty_cache()

        print()

    def convolution_performance(self) -> None:
        """Test convolution performance for deep learning"""
        print("🖼️  CONVOLUTION PERFORMANCE")
        print("-" * 50)

        batch_size = 32 if self.gpu_available else 8

        # Common CNN layer configurations
        configs: list[tuple[int, int, int, str]] = [
            (3, 64, 224, "First conv layer"),
            (64, 128, 112, "Mid conv layer"),
            (256, 512, 56, "Deep conv layer"),
            (512, 1024, 28, "Very deep conv layer")
        ]

        for in_ch, out_ch, img_size, desc in configs:
            print(f"📊 {desc}: {in_ch}→{out_ch}, {img_size}x{img_size}")

            # Create input and convolution
            x = torch.randn(batch_size, in_ch, img_size, img_size, device=self.device)
            conv = nn.Conv2d(in_ch, out_ch, 3, padding=1).to(self.device)

            # Warm up
            if self.gpu_available and hasattr(torch, 'autocast'):
                with torch.autocast('cuda'):
                    _ = conv(x)
            else:
                _ = conv(x)
            if self.gpu_available:
                torch.cuda.synchronize()

            # Benchmark
            start = time.time()
            if self.gpu_available and hasattr(torch, 'autocast'):
                with torch.autocast('cuda'):
                    output = conv(x)
            else:
                output = conv(x)
            if self.gpu_available:
                torch.cuda.synchronize()
            conv_time = time.time() - start

            # Calculate approximate FLOPS
            flops = batch_size * out_ch * img_size * img_size * in_ch * 9  # 3x3 kernel
            gflops = flops / conv_time / 1e9

            print(f"   ⏱️  Time: {conv_time:.4f}s")
            print(f"   ⚡ Performance: {gflops:.1f} GFLOPS")
            print(f"   📐 Output shape: {list(output.shape)}")

            del x, conv, output
            if self.gpu_available:
                torch.cuda.empty_cache()

        print()

    def run_complete_benchmark(self) -> None:
        """Run all benchmarks"""
        self.show_gpu_specs()

        total_start = time.time()

        # Run all benchmarks
        self.benchmark_matrix_sizes()
        self.neural_network_training_demo()
        self.advanced_tensor_operations()
        self.convolution_performance()

        if self.gpu_available:
            self.memory_throughput_test()

        total_time = time.time() - total_start

        # Final summary
        print("🏆 BENCHMARK COMPLETE!")
        print("=" * 60)
        print(f"⏱️  Total execution time: {total_time:.2f} seconds")

        if self.gpu_available:
            memory_used = torch.cuda.memory_allocated() / (1024**3)
            memory_cached = torch.cuda.memory_reserved() / (1024**3)
            print(f"💾 GPU memory used: {memory_used:.2f} GB")
            print(f"💾 GPU memory cached: {memory_cached:.2f} GB")

            # Show utilization estimate
            props = torch.cuda.get_device_properties(0)
            print(f"🔥 Your GPU is a computational MONSTER!")
            print(f"   {torch.cuda.get_device_name(0)}")
            print(f"   {props.total_memory/(1024**3):.1f} GB VRAM")
            print(f"   {props.multi_processor_count} SMs")
        else:
            print("💻 CPU performance demonstrated")


def main() -> None:
    """Main function"""
    demo = GPUPerformanceDemo()
    demo.run_complete_benchmark()


if __name__ == "__main__":
    main()
