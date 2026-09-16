# SC-BURST-RDMA-001: Zero-Copy RDMA Offload and Heijunka High-Burst Benchmark Mandate

- **Rule Identifier**: `SC-BURST-RDMA-001`
- **Sub-Rules**: `SC-RDMA-ARENA-001` (BEAM Arena Retention), `SC-RDMA-NOTE-001` (Transition Note), `SC-HEIJUNKA-BURST-001` (Batch Stealing Operads), `SC-BURST-BENCH-001` (High-Burst Benchmarks)
- **Specification**: `docs/design/20260916-1950-zero-copy-rdma-offload-design-note.md` (`NOTE-ZERO-COPY-RDMA-001`)
- **Decision Record**: `docs/zk/20260916-1950-adr-134-zero-copy-rdma-offload-and-heijunka-burst-benchmarks.md` (`ADR-134`)
- **Tailscale Link**: [http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260916-1950-zero-copy-rdma-and-burst-benchmark-mandate.md](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260916-1950-zero-copy-rdma-and-burst-benchmark-mandate.md)
- **Lean 4 Proofs**: [`formal/lean/Burst_Work_Stealing_And_RDMA_Offload.lean`](file:///home/an/NAS-setup/uos/formal/lean/Burst_Work_Stealing_And_RDMA_Offload.lean)
- **Authority**: Codex Astra (`codex-astra`) & Claude Fable (`L0-fable`) Tri-Sovereign Consensus

#fractal-l0 #fractal-l1 #fractal-l4 #fractal-l6 #zero-muda #rdma #heijunka #burst #benchmarks #tailscale-web

---

## 1. Principle & Scope

Per operator directive, the system MUST retain BEAM VM memory arena abstractions while specifying zero-copy RoCEv2/InfiniBand RDMA offload and executing high-burst benchmarks:

1. **BEAM VM Arena Abstraction (`SC-RDMA-ARENA-001`)**:
   - `apps/cepaf_gleam/src/cepaf_gleam/ai/distributed_tensor_monoid.gleam` MUST retain off-heap reference-counted binary arenas, guaranteeing zero GC interference for AI tensor allocations.
2. **Transition Design Note (`SC-RDMA-NOTE-001`)**:
   - The repository MUST maintain `docs/design/20260916-1950-zero-copy-rdma-offload-design-note.md` detailing future Linux `ibverbs` page-locking (`ibv_reg_mr`), 64-byte alignment, and scatter/gather DMA transfers.
3. **Heijunka Batch Work-Stealing Operads (`SC-HEIJUNKA-BURST-001`)**:
   - `apps/cepaf_gleam/src/cepaf_gleam/planning/heijunka_work_stealing.gleam` MUST implement batch task redistribution without overshooting target transfer load, strictly contracting cluster queue skew.
4. **High-Burst Benchmark Protocol (`SC-BURST-BENCH-001`)**:
   - `apps/cepaf_gleam/test/heijunka_burst_benchmark_test.gleam` MUST execute and pass 100, 500, and 1,000 tasks burst workloads across heterogeneous worker queues, maintaining $>60\%$ skew contraction and 100% Pareto compliance.

---

## 2. Invariant Rules

### Invariant 1: Batch Work-Stealing Contraction (`INV-BURST-01`)
$$\text{load}(\text{steal\_batch}(q, s)) \le \text{load}(q)$$
Machine-checked by Lean 4 theorem `batch_work_stealing_skew_contraction`.

### Invariant 2: Cluster Skew Reduction (`INV-BURST-02`)
$$\text{max\_load}(\text{apply\_transfer}(c, t)) \le \text{max\_load}(c)$$
Machine-checked by Lean 4 theorem `cluster_multi_worker_skew_bound`.

### Invariant 3: Workload & Task Count Conservation (`INV-BURST-03`)
$$(n_1 - k) + (n_2 + k) = n_1 + n_2$$
Machine-checked by Lean 4 theorem `burst_workload_conservation`.

### Invariant 4: 64-Byte Hardware Cache Line Alignment (`INV-BURST-04`)
$$(k \times 64) \pmod{64} == 0$$
Machine-checked by Lean 4 theorem `rdma_offload_mr_registration_alignment`.

### Invariant 5: Storage Hardware Interlock (`INV-BURST-05`)
The host root OS NVMe drive serial `HARD_DENIED_SYSTEM_OS_SERIAL` (`[REDACTED_SYSTEM_OS_SERIAL]`) is unconditionally barred and fails closed against any storage memory registration or command. Machine-checked by Lean 4 theorem `stamp_root_nvme_serial_hard_denied`.
