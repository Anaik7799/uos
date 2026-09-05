# UOS Kubernetes & Rook-Ceph Storage Cutover Runbook (EV-15)

- **Document ID:** `UOS-K8S-STORAGE-CUTOVER-2026-09-05`
- **Timestamp:** `2026-09-05T16:57:15+02:00` (UTC: `2026-09-05T14:57:15Z`)
- **Authority:** Operator Explicit Authorization Required
- **Prerequisite:** EV-14 Harness Parity Battery verified 100% GREEN (zero divergence)

---

## 1. Safety Invariants & Hardware Guards

1. **Root Drive Protection Invariant:**
   - Protected Hardware Serial: `25503L801736` (Host OS NVMe root partition).
   - Protected EUI-64: `eui.e8238fa6bf530001001b448b4f783cdb`.
   - **Enforcement:** Zero automation is permitted to execute `wipefs`, `sgdisk --zap-all`, or Ceph OSD allocation against any device resolving to serial `25503L801736`.
   - **Verification:** Tested by `tests/hardware_identity_test.rs` (3/3 unit tests pass).

2. **Allowed Storage Candidates:**
   - Candidate NVMe Serial: `25503L802767` (Secondary 1.92TB NVMe drive).
   - Mandatory device resolution via `/dev/disk/by-id/nvme-*`, never bare `/dev/nvme0n1` or `/dev/sda`.

---

## 2. Pre-Cutover Verification Checklist

- [x] EV-01..EV-13 sealed in Jujutsu.
- [x] EV-14 Hermes/ZigVM parity harness passing:
  - `test_parity_algebra.exe`: 146/146 passed.
  - `test_parity_compare.exe`: 201/201 passed.
  - `test_parity_ledger.exe`: 13/13 passed.
  - `test_parity_dashboard.exe`: 49/49 passed.
- [x] Live MCP control loop green: discriminator `run=ok formal=8/8 safety_ucas=54`.
- [x] Zero-Muda verified: 0 Bevy, 0 Graphite across all source trees.
- [x] Gleam root supervisor (`uos_sup.gleam`) active and verified.

---

## 3. Physical Storage & Cluster Boot Sequence

When authorized by the operator:

### Phase 1: Storage Node Preflight
```bash
# 1. Verify immutable serial of target secondary disk
ls -l /dev/disk/by-id/ | grep -i "25503L802767"

# 2. Confirm root OS disk serial is strictly untouched
ls -l /dev/disk/by-id/ | grep -i "25503L801736"
```

### Phase 2: Ceph Cluster Manifest Application
Apply Rook-Ceph cluster definitions from `ops/kubernetes/nas-k8s-lab/`:
```bash
kubectl apply -f ops/kubernetes/nas-k8s-lab/crds.yaml
kubectl apply -f ops/kubernetes/nas-k8s-lab/common.yaml
kubectl apply -f ops/kubernetes/nas-k8s-lab/operator.yaml
kubectl apply -f ops/kubernetes/nas-k8s-lab/cluster.yaml
```

### Phase 3: Post-Cutover Health Check
Verify cluster and storage health:
```bash
kubectl -n rook-ceph get cephcluster
kubectl get nodes -o wide
kubectl get pods -A
```
