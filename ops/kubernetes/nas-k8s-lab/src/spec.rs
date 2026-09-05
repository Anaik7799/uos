#[derive(Debug, Clone)]
pub struct LabSpec {
    pub host: HostSpec,
    pub kubernetes: KubernetesSpec,
    pub ceph: CephSpec,
    pub platform: PlatformSpec,
    pub vms: Vec<VmSpec>,
}

#[derive(Debug, Clone)]
pub struct HostSpec {
    pub name: &'static str,
    pub os_disk: &'static str,
    pub lab_network_name: &'static str,
    pub lab_cidr: &'static str,
    pub host_lab_ip: &'static str,
    pub api_endpoint: &'static str,
    pub api_port: u16,
}

#[derive(Debug, Clone)]
pub struct KubernetesSpec {
    pub version: &'static str,
    pub pod_cidr: &'static str,
    pub service_cidr: &'static str,
    pub cni: &'static str,
    pub control_plane_endpoint: &'static str,
}

#[derive(Debug, Clone)]
pub struct CephSpec {
    pub rook_version: &'static str,
    pub namespace: &'static str,
    pub cluster_name: &'static str,
    pub default_block_class: &'static str,
    pub filesystem_name: &'static str,
    pub object_store_name: &'static str,
}

#[derive(Debug, Clone)]
pub struct PlatformSpec {
    pub namespaces: Vec<&'static str>,
}

#[derive(Debug, Clone)]
pub struct VmSpec {
    pub name: &'static str,
    pub ip: &'static str,
    pub vcpus: u8,
    pub memory_mib: u32,
    pub os_disk_gib: u16,
    pub osd_devices: Vec<OsdDevice>,
}

#[derive(Debug, Clone)]
pub struct OsdDevice {
    pub host_device: &'static str,
    pub class: &'static str,
}

impl Default for LabSpec {
    fn default() -> Self {
        Self {
            host: HostSpec {
                name: "nas-1",
                os_disk: "/dev/nvme0n1",
                lab_network_name: "k8s-lab",
                lab_cidr: "10.30.0.0/24",
                host_lab_ip: "10.30.0.1",
                api_endpoint: "10.30.0.1",
                api_port: 6443,
            },
            kubernetes: KubernetesSpec {
                version: "v1.34",
                pod_cidr: "10.42.0.0/16",
                service_cidr: "10.43.0.0/16",
                cni: "cilium",
                control_plane_endpoint: "10.30.0.1:6443",
            },
            ceph: CephSpec {
                rook_version: "v1.19.4",
                namespace: "rook-ceph",
                cluster_name: "rook-ceph",
                default_block_class: "ceph-block-hdd",
                filesystem_name: "ceph-filesystem",
                object_store_name: "ceph-objectstore",
            },
            platform: PlatformSpec {
                namespaces: vec![
                    "rook-ceph",
                    "ingress-nginx",
                    "cert-manager",
                    "argocd",
                    "monitoring",
                    "tailscale",
                ],
            },
            vms: vec![
                VmSpec {
                    name: "k8s-cp1",
                    ip: "10.30.0.11",
                    vcpus: 6,
                    memory_mib: 12_288,
                    os_disk_gib: 80,
                    osd_devices: vec![
                        OsdDevice {
                            host_device: "/dev/nvme1n1",
                            class: "nvme",
                        },
                        OsdDevice {
                            host_device: "/dev/sda",
                            class: "hdd",
                        },
                    ],
                },
                VmSpec {
                    name: "k8s-cp2",
                    ip: "10.30.0.12",
                    vcpus: 6,
                    memory_mib: 10_240,
                    os_disk_gib: 80,
                    osd_devices: vec![
                        OsdDevice {
                            host_device: "/dev/sdb",
                            class: "hdd",
                        },
                        OsdDevice {
                            host_device: "/dev/sdc",
                            class: "hdd",
                        },
                    ],
                },
                VmSpec {
                    name: "k8s-cp3",
                    ip: "10.30.0.13",
                    vcpus: 6,
                    memory_mib: 10_240,
                    os_disk_gib: 80,
                    osd_devices: vec![OsdDevice {
                        host_device: "/dev/sdd",
                        class: "hdd",
                    }],
                },
            ],
        }
    }
}

impl LabSpec {
    pub fn summary(&self) -> String {
        let mut out = String::new();
        out.push_str("NAS Kubernetes/Rook-Ceph VM lab\n");
        out.push_str(&format!(
            "host: {} (OS disk: {})\n",
            self.host.name, self.host.os_disk
        ));
        out.push_str(&format!(
            "network: {} {}\n",
            self.host.lab_network_name, self.host.lab_cidr
        ));
        out.push_str(&format!(
            "kubernetes: {} via kubeadm, CNI={}\n",
            self.kubernetes.version, self.kubernetes.cni
        ));
        out.push_str(&format!(
            "rook: {} in namespace {}\n",
            self.ceph.rook_version, self.ceph.namespace
        ));
        out.push_str("VMs:\n");
        for vm in &self.vms {
            let devices = vm
                .osd_devices
                .iter()
                .map(|d| format!("{}:{}", d.host_device, d.class))
                .collect::<Vec<_>>()
                .join(", ");
            out.push_str(&format!(
                "- {} {}: {} vCPU, {} MiB RAM, {} GiB OS, OSDs [{}]\n",
                vm.name, vm.ip, vm.vcpus, vm.memory_mib, vm.os_disk_gib, devices
            ));
        }
        out.push_str("safety: audit legacy storage before any wipe or passthrough\n");
        out
    }

    pub const HARD_DENIED_SYSTEM_OS_SERIAL: &'static str = "25503L801736";

    pub fn validate_safety_invariants(&self) -> Result<(), &'static str> {
        for vm in &self.vms {
            for osd in &vm.osd_devices {
                if osd.host_device == self.host.os_disk {
                    return Err("HARD_DENIED: OSD device matches host OS root disk!");
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spec_safety_invariants_pass() {
        let spec = LabSpec::default();
        assert!(spec.validate_safety_invariants().is_ok());
    }

    #[test]
    fn test_spec_safety_invariants_fail_on_collision() {
        let mut spec = LabSpec::default();
        spec.vms[0].osd_devices[0].host_device = spec.host.os_disk;
        assert!(spec.validate_safety_invariants().is_err());
    }
}
