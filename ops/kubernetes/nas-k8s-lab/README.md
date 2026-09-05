# NAS Kubernetes Lab

Rust-only configuration tooling for the `nas-1` VM lab:

- 3 kubeadm Kubernetes control-plane VMs.
- Rook-Ceph runs inside Kubernetes.
- `nvme0n1` and `sda`-`sdd` are passed through as raw OSD devices only after the legacy audit is approved.
- Tailscale is the primary access path.

No Bash scripts are used here. Configuration is represented in Rust and rendered or applied by the `nas_k8s_lab` CLI.

## Commands

```text
cargo run --manifest-path k8s-lab/Cargo.toml -- summary
cargo run --manifest-path k8s-lab/Cargo.toml -- render
cargo run --manifest-path k8s-lab/Cargo.toml -- apply
```

`render` writes generated files under `k8s-lab/rendered/`. These files are generated artifacts and can be inspected before any privileged host operation.

`apply` uses `kube-rs` and the active kubeconfig to create Kubernetes namespaces, default Ceph storage classes, and Rook custom resources. It assumes the Kubernetes API is already reachable and the Rook CRDs/operator are installed.

## Safety Gate

Do not attach or wipe OSD disks until the legacy audit has been reviewed. The intended candidate devices are:

- `/dev/nvme0n1`
- `/dev/sda`
- `/dev/sdb`
- `/dev/sdc`
- `/dev/sdd`

The OS remains on `/dev/nvme1n1`.
