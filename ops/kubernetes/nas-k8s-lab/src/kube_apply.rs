use crate::spec::LabSpec;
use anyhow::Result;
use k8s_openapi::api::core::v1::Namespace;
use k8s_openapi::api::storage::v1::StorageClass;
use k8s_openapi::apimachinery::pkg::apis::meta::v1::ObjectMeta;
use kube::api::{Patch, PatchParams};
use kube::core::{ApiResource, DynamicObject, GroupVersionKind};
use kube::{Api, Client};
use serde_json::json;
use std::collections::BTreeMap;

pub async fn apply_all(spec: &LabSpec) -> Result<()> {
    let client = Client::try_default().await?;
    apply_namespaces(client.clone(), spec).await?;
    apply_rook_resources(client.clone(), spec).await?;
    apply_storage_classes(client.clone(), spec).await?;
    println!("Applied Kubernetes base configuration with kube-rs");
    println!(
        "Rook CRDs/operator {} must already be installed.",
        spec.ceph.rook_version
    );
    Ok(())
}

async fn apply_namespaces(client: Client, spec: &LabSpec) -> Result<()> {
    let namespaces: Api<Namespace> = Api::all(client);
    let pp = PatchParams::apply("nas-k8s-lab").force();

    for name in &spec.platform.namespaces {
        let ns = Namespace {
            metadata: ObjectMeta {
                name: Some((*name).to_string()),
                labels: Some(BTreeMap::from([(
                    "app.kubernetes.io/managed-by".to_string(),
                    "nas-k8s-lab-rust".to_string(),
                )])),
                ..ObjectMeta::default()
            },
            ..Namespace::default()
        };
        namespaces.patch(name, &pp, &Patch::Apply(&ns)).await?;
    }
    Ok(())
}

async fn apply_rook_resources(client: Client, spec: &LabSpec) -> Result<()> {
    apply_dynamic(
        client.clone(),
        spec.ceph.namespace,
        "CephCluster",
        "cephclusters",
        spec.ceph.cluster_name,
        rook_cluster_spec(spec),
    )
    .await?;
    apply_dynamic(
        client.clone(),
        spec.ceph.namespace,
        "CephBlockPool",
        "cephblockpools",
        "hdd-pool",
        rook_block_pool_spec("hdd", 3, 2),
    )
    .await?;
    apply_dynamic(
        client.clone(),
        spec.ceph.namespace,
        "CephBlockPool",
        "cephblockpools",
        "nvme-scratch-pool",
        rook_block_pool_spec("nvme", 1, 1),
    )
    .await?;
    apply_dynamic(
        client.clone(),
        spec.ceph.namespace,
        "CephFilesystem",
        "cephfilesystems",
        spec.ceph.filesystem_name,
        rook_filesystem_spec(),
    )
    .await?;
    apply_dynamic(
        client,
        spec.ceph.namespace,
        "CephObjectStore",
        "cephobjectstores",
        spec.ceph.object_store_name,
        rook_object_store_spec(),
    )
    .await?;
    Ok(())
}

async fn apply_dynamic(
    client: Client,
    namespace: &str,
    kind: &str,
    plural: &str,
    name: &str,
    spec: serde_json::Value,
) -> Result<()> {
    let gvk = GroupVersionKind::gvk("ceph.rook.io", "v1", kind);
    let ar = ApiResource::from_gvk_with_plural(&gvk, plural);
    let api: Api<DynamicObject> = Api::namespaced_with(client, namespace, &ar);
    let pp = PatchParams::apply("nas-k8s-lab").force();
    let obj = DynamicObject::new(name, &ar)
        .within(namespace)
        .data(json!({ "spec": spec }));
    api.patch(name, &pp, &Patch::Apply(&obj)).await?;
    Ok(())
}

async fn apply_storage_classes(client: Client, spec: &LabSpec) -> Result<()> {
    let storage_classes: Api<StorageClass> = Api::all(client);
    let pp = PatchParams::apply("nas-k8s-lab").force();

    let hdd = ceph_rbd_storage_class(spec.ceph.default_block_class, "hdd-pool", true, "Delete");
    storage_classes
        .patch(spec.ceph.default_block_class, &pp, &Patch::Apply(&hdd))
        .await?;

    let nvme = ceph_rbd_storage_class(
        "ceph-block-nvme-scratch",
        "nvme-scratch-pool",
        false,
        "Delete",
    );
    storage_classes
        .patch("ceph-block-nvme-scratch", &pp, &Patch::Apply(&nvme))
        .await?;

    Ok(())
}

fn rook_cluster_spec(spec: &LabSpec) -> serde_json::Value {
    let nodes = spec
        .vms
        .iter()
        .map(|vm| {
            json!({
                "name": vm.name,
                "devices": vm.osd_devices.iter().enumerate().map(|(i, dev)| {
                    json!({
                        "name": format!("vd{}", (b'b' + i as u8) as char),
                        "config": { "deviceClass": dev.class }
                    })
                }).collect::<Vec<_>>()
            })
        })
        .collect::<Vec<_>>();

    json!({
        "cephVersion": { "image": "quay.io/ceph/ceph:v19" },
        "dataDirHostPath": "/var/lib/rook",
        "dashboard": { "enabled": true },
        "mon": { "count": 3, "allowMultiplePerNode": false },
        "storage": { "useAllNodes": false, "useAllDevices": false, "nodes": nodes }
    })
}

fn rook_block_pool_spec(device_class: &str, size: u8, min_size: u8) -> serde_json::Value {
    json!({
        "failureDomain": "host",
        "deviceClass": device_class,
        "replicated": { "size": size, "requireSafeReplicaSize": size > 1 },
        "parameters": { "min_size": min_size.to_string() }
    })
}

fn rook_filesystem_spec() -> serde_json::Value {
    json!({
        "metadataPool": { "replicated": { "size": 3 } },
        "dataPools": [{ "name": "data0", "deviceClass": "hdd", "replicated": { "size": 3 } }],
        "metadataServer": { "activeCount": 1, "activeStandby": true }
    })
}

fn rook_object_store_spec() -> serde_json::Value {
    json!({
        "metadataPool": { "deviceClass": "hdd", "replicated": { "size": 3 } },
        "dataPool": { "deviceClass": "hdd", "replicated": { "size": 3 } },
        "gateway": { "port": 80, "instances": 1 }
    })
}

fn ceph_rbd_storage_class(
    name: &str,
    pool: &str,
    default_class: bool,
    reclaim_policy: &str,
) -> StorageClass {
    let mut annotations = BTreeMap::new();
    if default_class {
        annotations.insert(
            "storageclass.kubernetes.io/is-default-class".to_string(),
            "true".to_string(),
        );
    }

    StorageClass {
        metadata: ObjectMeta {
            name: Some(name.to_string()),
            annotations: Some(annotations),
            labels: Some(BTreeMap::from([(
                "app.kubernetes.io/managed-by".to_string(),
                "nas-k8s-lab-rust".to_string(),
            )])),
            ..ObjectMeta::default()
        },
        provisioner: "rook-ceph.rbd.csi.ceph.com".to_string(),
        reclaim_policy: Some(reclaim_policy.to_string()),
        volume_binding_mode: Some("WaitForFirstConsumer".to_string()),
        allow_volume_expansion: Some(true),
        parameters: Some(BTreeMap::from([
            ("clusterID".to_string(), "rook-ceph".to_string()),
            ("pool".to_string(), pool.to_string()),
            ("imageFormat".to_string(), "2".to_string()),
            ("imageFeatures".to_string(), "layering".to_string()),
            ("csi.storage.k8s.io/fstype".to_string(), "ext4".to_string()),
        ])),
        ..StorageClass::default()
    }
}
