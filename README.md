# Run object detection faster than numpy
- Model: YOLOv2-tiny

**Baselines**
- Naive scalar operations
- Full vectorized NumPy

**CPU optimization**
- OpenBLAS
- AVX (main): Runs 30% slower to NumPy

**GPU optimization**
- cuBLAS
- CUDA (main): Runs 2x faster to NumPy
