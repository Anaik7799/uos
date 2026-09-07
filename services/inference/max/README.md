# Supervised Service: `inference/max`

- **Description**: Isolated Modular MAX / Mojo high-performance inference daemon.
- **Engine Lineage**: Modular MAX `max/v26.5.0` and Mojo `mojo/v1.0.0` pinned platform closure.
- **Boundary**: Isolated child process supervised by Gleam/OTP via 4-byte big-endian length-delimited framing over stdio pipes or UNIX domain socket.
- **Hardware Acceleration**: Mojo SIMD kernel (`services/inference/max/max_kernel.mojo`) for tensor operations, vector dot products, cosine similarities, and Raga acoustic synthesis.
- **Governance**: Zero-Muda compliant (0 Bevy, 0 Graphite). Python is strictly quarantined to this directory (`services/inference/max/max_worker.py`).

## Supported RPC Methods (8-Method Contract)

1. `health`: Runtime health, engine version, and active modalities.
2. `metrics`: QPS throughput, P99 latency, and active tensor allocations.
3. `modalities`: Modality capabilities (`text`, `image`, `audio`, `video`, `embedding`).
4. `infer_text`: LLM cognitive analysis and planning conflict detection.
5. `infer_audio`: Authentic Indian Classical Raga synthesis (Durga, Bhairav, Yaman) with continuous Meend $S$-curve glissando and Tanpura Jawari shimmer.
6. `infer_image`: Multimodal vision tensor processing.
7. `infer_video`: Spatiotemporal frame analysis and anomaly scoring.
8. `embed`: High-dimensional dense vector embeddings with L2 normalization for Hermes Wiki and ZigVM ZK semantic search.

## Verification & Benchmarks

```bash
# In-process self-check
python3 services/inference/max/max_worker.py --selfcheck

# High-throughput benchmark
python3 services/inference/max/max_worker.py --bench
```
