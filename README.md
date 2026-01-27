# Casascius S1 Valid Minikeys CUDA Generator

A high-performance CUDA tool specifically designed to generate valid **Casascius Series 1 MiniKeys**. These keys are 22-character strings starting with 'S' that satisfy the specific SHA-256 checksum requirement required for Casascius physical bitcoins.

## 🚀 Features

*   **Algorithm:** Optimized SHA-256 implementation scanning for the `hash[0] == 0x00` condition.
*   **Performance:**
    *   Uses `atomicAdd` for thread-safe result extraction.
    *   Massive parallelism with 2048 blocks and 256 threads per kernel.
    *   Hybrid generation: Host rotates prefixes (Y/X patterns) while GPU brute-forces suffixes.
*   **Multi-GPU Support:** Automatically detects and utilizes multiple NVIDIA GPUs.
*   **Zero-Copy I/O:** Optimized `stdout` buffering for piping results to files without slowing down the generator.

## 🛠️ Build

### Prerequisites
*   NVIDIA GPU (Compute Capability 5.0+)
*   CUDA Toolkit (11.0+)
*   Windows (MSVC) or Linux (NVCC)

### Compilation
```bash
nvcc -O3 -o casascius_s1_gen main.cu
nvcc -O3 -arch=sm_86 -o casascius_gen.exe main.cu


### Usage
./casascius_s1_gen > keys.txt

# Select specific GPU IDs (e.g., GPU 0 and 2)
./casascius_s1_gen -d 0,2 > keys.txt

# Use on pipe
./casascius_s1_gen -d 0 | brainflayer.......
