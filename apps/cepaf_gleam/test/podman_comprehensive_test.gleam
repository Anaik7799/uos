// Podman Comprehensive Test Suite
// Tests for L4_SYSTEM podman domain types, container parsing, volumes, networks.
// SC-CNT-001, SC-ARCH-SPLIT-001
// Coverage: container status conversions, domain type constructors,
//           volume specs, network specs, mount types, port mappings.

import cepaf_gleam/podman/domain
import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// C1: ContainerStatus — string_to_status conversions
// =============================================================================

pub fn status_running_test() {
  domain.string_to_status("running")
  |> should.equal(domain.Running)
}

pub fn status_created_test() {
  domain.string_to_status("created")
  |> should.equal(domain.Created)
}

pub fn status_paused_test() {
  domain.string_to_status("paused")
  |> should.equal(domain.Paused)
}

pub fn status_restarting_test() {
  domain.string_to_status("restarting")
  |> should.equal(domain.Restarting)
}

pub fn status_removing_test() {
  domain.string_to_status("removing")
  |> should.equal(domain.Removing)
}

pub fn status_exited_test() {
  domain.string_to_status("exited")
  |> should.equal(domain.Exited(0))
}

pub fn status_dead_test() {
  domain.string_to_status("dead")
  |> should.equal(domain.Dead("unknown"))
}

pub fn status_unknown_test() {
  domain.string_to_status("something_weird")
  |> should.equal(domain.Unknown("something_weird"))
}

// =============================================================================
// C2: status_to_string — round-trip
// =============================================================================

pub fn status_to_string_running_test() {
  domain.status_to_string(domain.Running)
  |> should.equal("running")
}

pub fn status_to_string_created_test() {
  domain.status_to_string(domain.Created)
  |> should.equal("created")
}

pub fn status_to_string_paused_test() {
  domain.status_to_string(domain.Paused)
  |> should.equal("paused")
}

pub fn status_to_string_exited_test() {
  domain.status_to_string(domain.Exited(1))
  |> should.equal("exited")
}

pub fn status_to_string_dead_test() {
  domain.status_to_string(domain.Dead("OOM"))
  |> should.equal("dead")
}

pub fn status_to_string_unknown_test() {
  domain.status_to_string(domain.Unknown("degraded"))
  |> should.equal("degraded")
}

pub fn status_roundtrip_running_test() {
  domain.Running
  |> domain.status_to_string()
  |> domain.string_to_status()
  |> should.equal(domain.Running)
}

pub fn status_roundtrip_paused_test() {
  domain.Paused
  |> domain.status_to_string()
  |> domain.string_to_status()
  |> should.equal(domain.Paused)
}

// =============================================================================
// C3: HealthStatus conversions
// =============================================================================

pub fn health_starting_test() {
  domain.string_to_health_status("starting")
  |> should.equal(domain.Starting)
}

pub fn health_healthy_test() {
  domain.string_to_health_status("healthy")
  |> should.equal(domain.Healthy)
}

pub fn health_unhealthy_test() {
  domain.string_to_health_status("unhealthy")
  |> should.equal(domain.Unhealthy(0))
}

pub fn health_none_test() {
  domain.string_to_health_status("none")
  |> should.equal(domain.NoHealthcheck)
}

pub fn health_empty_string_test() {
  domain.string_to_health_status("")
  |> should.equal(domain.NoHealthcheck)
}

pub fn health_unknown_test() {
  domain.string_to_health_status("weird_status")
  |> should.equal(domain.UnknownHealth("weird_status"))
}

pub fn health_to_string_healthy_test() {
  domain.health_status_to_string(domain.Healthy)
  |> should.equal("healthy")
}

pub fn health_to_string_starting_test() {
  domain.health_status_to_string(domain.Starting)
  |> should.equal("starting")
}

pub fn health_to_string_unhealthy_test() {
  domain.health_status_to_string(domain.Unhealthy(3))
  |> should.equal("unhealthy")
}

pub fn health_to_string_no_healthcheck_test() {
  domain.health_status_to_string(domain.NoHealthcheck)
  |> should.equal("none")
}

// =============================================================================
// C4: ContainerSummary constructor
// =============================================================================

pub fn container_summary_construction_test() {
  let container =
    domain.ContainerSummary(
      id: "abc123",
      names: ["my-container"],
      image: "ubuntu:22.04",
      image_id: "sha256:deadbeef",
      command: "/bin/bash",
      created: 1_700_000_000,
      state: domain.Running,
      status: "Up 2 hours",
      ports: [],
      labels: dict.new(),
      mounts: [],
      networks: ["podman"],
    )
  container.id
  |> should.equal("abc123")
  container.image
  |> should.equal("ubuntu:22.04")
}

pub fn container_summary_multiple_names_test() {
  let container =
    domain.ContainerSummary(
      id: "def456",
      names: ["svc-a", "svc-alias"],
      image: "postgres:15",
      image_id: "",
      command: "postgres",
      created: 0,
      state: domain.Running,
      status: "Up",
      ports: [],
      labels: dict.new(),
      mounts: [],
      networks: [],
    )
  list.length(container.names)
  |> should.equal(2)
}

import gleam/list

pub fn container_summary_labels_test() {
  let labels = dict.from_list([#("app", "c3i"), #("layer", "L4_SYSTEM")])
  let container =
    domain.ContainerSummary(
      id: "xyz",
      names: ["c3i-core"],
      image: "c3i:latest",
      image_id: "",
      command: "",
      created: 0,
      state: domain.Created,
      status: "Created",
      ports: [],
      labels: labels,
      mounts: [],
      networks: [],
    )
  dict.size(container.labels)
  |> should.equal(2)
}

// =============================================================================
// C5: is_stateful — mount-based stateful detection
// =============================================================================

pub fn is_stateful_no_mounts_test() {
  let container =
    domain.ContainerSummary(
      id: "s1",
      names: ["stateless"],
      image: "nginx",
      image_id: "",
      command: "",
      created: 0,
      state: domain.Running,
      status: "Up",
      ports: [],
      labels: dict.new(),
      mounts: [],
      networks: [],
    )
  domain.is_stateful(container)
  |> should.be_false()
}

pub fn is_stateful_postgresql_mount_test() {
  let pg_mount =
    domain.Mount(
      mount_type: domain.MountVolume,
      source: "pgdata",
      target: "/var/lib/postgresql/data",
      read_only: False,
      options: [],
    )
  let container =
    domain.ContainerSummary(
      id: "pg1",
      names: ["db-prod"],
      image: "postgres:15",
      image_id: "",
      command: "",
      created: 0,
      state: domain.Running,
      status: "Up",
      ports: [],
      labels: dict.new(),
      mounts: [pg_mount],
      networks: [],
    )
  domain.is_stateful(container)
  |> should.be_true()
}

pub fn is_stateful_data_db_mount_test() {
  let db_mount =
    domain.Mount(
      mount_type: domain.Bind,
      source: "/host/data",
      target: "/data/db",
      read_only: False,
      options: [],
    )
  let container =
    domain.ContainerSummary(
      id: "m1",
      names: ["mongo"],
      image: "mongo:7",
      image_id: "",
      command: "",
      created: 0,
      state: domain.Running,
      status: "Up",
      ports: [],
      labels: dict.new(),
      mounts: [db_mount],
      networks: [],
    )
  domain.is_stateful(container)
  |> should.be_true()
}

pub fn is_stateful_tmp_mount_is_not_stateful_test() {
  let tmp_mount =
    domain.Mount(
      mount_type: domain.Tmpfs,
      source: "",
      target: "/tmp/cache",
      read_only: False,
      options: [],
    )
  let container =
    domain.ContainerSummary(
      id: "tmp1",
      names: ["cache"],
      image: "redis",
      image_id: "",
      command: "",
      created: 0,
      state: domain.Running,
      status: "Up",
      ports: [],
      labels: dict.new(),
      mounts: [tmp_mount],
      networks: [],
    )
  domain.is_stateful(container)
  |> should.be_false()
}

// =============================================================================
// C6: PortMapping constructor
// =============================================================================

pub fn port_mapping_tcp_test() {
  let pm =
    domain.PortMapping(
      container_port: 5432,
      host_port: option.Some(5433),
      host_ip: option.Some("0.0.0.0"),
      protocol: domain.Tcp,
      range: option.None,
    )
  pm.container_port
  |> should.equal(5432)
  pm.host_port
  |> should.equal(option.Some(5433))
}

pub fn port_mapping_udp_test() {
  let pm =
    domain.PortMapping(
      container_port: 4317,
      host_port: option.None,
      host_ip: option.None,
      protocol: domain.Udp,
      range: option.None,
    )
  pm.protocol
  |> should.equal(domain.Udp)
}

// =============================================================================
// C7: Volume and VolumeSpec types
// =============================================================================

pub fn volume_spec_construction_test() {
  let spec =
    domain.VolumeSpec(
      name: "pgdata",
      driver: "local",
      labels: dict.from_list([#("managed-by", "c3i")]),
      options: dict.new(),
    )
  spec.name
  |> should.equal("pgdata")
  spec.driver
  |> should.equal("local")
}

pub fn volume_construction_test() {
  let vol =
    domain.Volume(
      name: "obsdata",
      driver: "local",
      mountpoint: "/var/lib/containers/storage/volumes/obsdata/_data",
      created_at: "2026-04-01T00:00:00Z",
      labels: dict.new(),
      options: dict.new(),
      scope: "local",
    )
  vol.name
  |> should.equal("obsdata")
  vol.scope
  |> should.equal("local")
}

// =============================================================================
// C8: Network and NetworkSpec types
// =============================================================================

pub fn subnet_construction_test() {
  let subnet =
    domain.Subnet(subnet: "10.88.0.0/16", gateway: option.Some("10.88.0.1"))
  subnet.subnet
  |> should.equal("10.88.0.0/16")
  subnet.gateway
  |> should.equal(option.Some("10.88.0.1"))
}

pub fn network_spec_construction_test() {
  let spec =
    domain.NetworkSpec(
      name: "c3i-mesh",
      driver: "bridge",
      internal: False,
      dns_enabled: True,
      subnets: [domain.Subnet(subnet: "192.168.100.0/24", gateway: option.None)],
      labels: dict.from_list([#("layer", "L6_ECOSYSTEM")]),
      options: dict.new(),
    )
  spec.name
  |> should.equal("c3i-mesh")
  spec.dns_enabled
  |> should.be_true()
  spec.internal
  |> should.be_false()
}

pub fn network_construction_test() {
  let net =
    domain.Network(
      name: "podman",
      id: "2f86d2eb4c3d",
      driver: "bridge",
      created: "2026-01-01T00:00:00Z",
      subnets: [],
      internal: False,
      dns_enabled: False,
      labels: dict.new(),
      options: dict.new(),
    )
  net.driver
  |> should.equal("bridge")
  net.id
  |> should.equal("2f86d2eb4c3d")
}

// =============================================================================
// C9: PodmanClientConfig defaults
// =============================================================================

pub fn default_config_api_version_test() {
  let cfg = domain.default_config()
  cfg.api_version
  |> should.equal("5.7.0")
}

pub fn default_config_timeout_test() {
  let cfg = domain.default_config()
  cfg.timeout_ms
  |> should.equal(30_000)
}

pub fn default_config_retry_count_test() {
  let cfg = domain.default_config()
  cfg.retry_count
  |> should.equal(3)
}

pub fn default_config_socket_rootless_test() {
  let cfg = domain.default_config()
  case cfg.socket {
    domain.Rootless(uid, _) ->
      uid
      |> should.equal("1000")
    domain.Rootful(_) -> should.fail()
  }
}

// =============================================================================
// C10: MountType variants
// =============================================================================

pub fn mount_type_bind_test() {
  let m =
    domain.Mount(
      mount_type: domain.Bind,
      source: "/host/path",
      target: "/container/path",
      read_only: True,
      options: ["ro"],
    )
  m.mount_type
  |> should.equal(domain.Bind)
  m.read_only
  |> should.be_true()
}

pub fn mount_type_tmpfs_test() {
  let m =
    domain.Mount(
      mount_type: domain.Tmpfs,
      source: "",
      target: "/tmp",
      read_only: False,
      options: [],
    )
  m.mount_type
  |> should.equal(domain.Tmpfs)
}

pub fn mount_type_volume_test() {
  let m =
    domain.Mount(
      mount_type: domain.MountVolume,
      source: "myvolume",
      target: "/data",
      read_only: False,
      options: [],
    )
  m.mount_type
  |> should.equal(domain.MountVolume)
}
