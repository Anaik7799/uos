// Podman domain types test — SC-ARCH-SPLIT-002
// Tests ContainerStatus, HealthStatus, PortMapping, Mount, PodmanClientConfig
// using verified public API from podman/domain.gleam

import cepaf_gleam/podman/domain.{
  Bind, Created, Dead, Devpts, Exited, Healthy, Image, Mount, MountVolume,
  NoHealthcheck, Paused, PodmanClientConfig, PortMapping, Removing, Restarting,
  Rootful, Rootless, Running, Sctp, Starting, Tcp, Tmpfs, Udp, Unhealthy,
  Unknown, UnknownHealth, default_config, health_status_to_string, is_stateful,
  status_to_string, string_to_health_status, string_to_status,
}
import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── ContainerStatus round-trips ──────────────────────────────────────────────

pub fn status_created_test() {
  status_to_string(Created)
  |> should.equal("created")
}

pub fn status_running_test() {
  status_to_string(Running)
  |> should.equal("running")
}

pub fn status_paused_test() {
  status_to_string(Paused)
  |> should.equal("paused")
}

pub fn status_restarting_test() {
  status_to_string(Restarting)
  |> should.equal("restarting")
}

pub fn status_removing_test() {
  status_to_string(Removing)
  |> should.equal("removing")
}

pub fn status_exited_test() {
  status_to_string(Exited(1))
  |> should.equal("exited")
}

pub fn status_dead_test() {
  status_to_string(Dead("oom"))
  |> should.equal("dead")
}

pub fn status_unknown_test() {
  status_to_string(Unknown("weirdstate"))
  |> should.equal("weirdstate")
}

pub fn string_to_status_created_test() {
  string_to_status("created")
  |> should.equal(Created)
}

pub fn string_to_status_running_test() {
  string_to_status("running")
  |> should.equal(Running)
}

pub fn string_to_status_exited_test() {
  string_to_status("exited")
  |> should.equal(Exited(0))
}

pub fn string_to_status_dead_test() {
  string_to_status("dead")
  |> should.equal(Dead("unknown"))
}

pub fn string_to_status_unknown_test() {
  string_to_status("bizarre")
  |> should.equal(Unknown("bizarre"))
}

// ── HealthStatus round-trips ──────────────────────────────────────────────────

pub fn health_starting_to_string_test() {
  health_status_to_string(Starting)
  |> should.equal("starting")
}

pub fn health_healthy_to_string_test() {
  health_status_to_string(Healthy)
  |> should.equal("healthy")
}

pub fn health_unhealthy_to_string_test() {
  health_status_to_string(Unhealthy(3))
  |> should.equal("unhealthy")
}

pub fn health_none_to_string_test() {
  health_status_to_string(NoHealthcheck)
  |> should.equal("none")
}

pub fn health_unknown_to_string_test() {
  health_status_to_string(UnknownHealth("?"))
  |> should.equal("?")
}

pub fn string_to_health_starting_test() {
  string_to_health_status("starting")
  |> should.equal(Starting)
}

pub fn string_to_health_healthy_test() {
  string_to_health_status("healthy")
  |> should.equal(Healthy)
}

pub fn string_to_health_unhealthy_test() {
  string_to_health_status("unhealthy")
  |> should.equal(Unhealthy(0))
}

pub fn string_to_health_none_test() {
  string_to_health_status("none")
  |> should.equal(NoHealthcheck)
}

pub fn string_to_health_empty_test() {
  string_to_health_status("")
  |> should.equal(NoHealthcheck)
}

pub fn string_to_health_unknown_test() {
  string_to_health_status("weird")
  |> should.equal(UnknownHealth("weird"))
}

// ── PortMapping construction ──────────────────────────────────────────────────

pub fn port_mapping_tcp_test() {
  let pm =
    PortMapping(
      container_port: 8080,
      host_port: Some(8080),
      host_ip: None,
      protocol: Tcp,
      range: None,
    )
  pm.container_port |> should.equal(8080)
  pm.protocol |> should.equal(Tcp)
}

pub fn port_mapping_udp_test() {
  let pm =
    PortMapping(
      container_port: 4317,
      host_port: None,
      host_ip: Some("0.0.0.0"),
      protocol: Udp,
      range: Some(5),
    )
  pm.protocol |> should.equal(Udp)
  pm.range |> should.equal(Some(5))
}

pub fn port_mapping_sctp_test() {
  let pm =
    PortMapping(
      container_port: 9999,
      host_port: None,
      host_ip: None,
      protocol: Sctp,
      range: None,
    )
  pm.protocol |> should.equal(Sctp)
}

// ── Mount construction ────────────────────────────────────────────────────────

pub fn mount_bind_test() {
  let m =
    Mount(
      mount_type: Bind,
      source: "/host/path",
      target: "/container/path",
      read_only: False,
      options: [],
    )
  m.mount_type |> should.equal(Bind)
  m.read_only |> should.equal(False)
}

pub fn mount_volume_test() {
  let m =
    Mount(
      mount_type: MountVolume,
      source: "myvolume",
      target: "/data",
      read_only: True,
      options: ["nocopy"],
    )
  m.mount_type |> should.equal(MountVolume)
  m.read_only |> should.equal(True)
}

pub fn mount_tmpfs_test() {
  let m =
    Mount(
      mount_type: Tmpfs,
      source: "",
      target: "/tmp",
      read_only: False,
      options: [],
    )
  m.mount_type |> should.equal(Tmpfs)
}

pub fn mount_image_test() {
  let m =
    Mount(
      mount_type: Image,
      source: "myimage:latest",
      target: "/img",
      read_only: True,
      options: [],
    )
  m.mount_type |> should.equal(Image)
}

pub fn mount_devpts_test() {
  let m =
    Mount(
      mount_type: Devpts,
      source: "",
      target: "/dev/pts",
      read_only: False,
      options: [],
    )
  m.mount_type |> should.equal(Devpts)
}

// ── is_stateful ───────────────────────────────────────────────────────────────

pub fn is_stateful_postgres_test() {
  let container =
    domain.ContainerSummary(
      id: "abc123",
      names: ["db-prod"],
      image: "postgres:17",
      image_id: "",
      command: "postgres",
      created: 0,
      state: Running,
      status: "running",
      ports: [],
      labels: dict.new(),
      mounts: [
        Mount(
          mount_type: MountVolume,
          source: "pgdata",
          target: "/var/lib/postgresql/data",
          read_only: False,
          options: [],
        ),
      ],
      networks: [],
    )
  is_stateful(container) |> should.equal(True)
}

pub fn is_stateful_mysql_test() {
  let container =
    domain.ContainerSummary(
      id: "db2",
      names: ["mysql"],
      image: "mysql:8",
      image_id: "",
      command: "mysqld",
      created: 0,
      state: Running,
      status: "running",
      ports: [],
      labels: dict.new(),
      mounts: [
        Mount(
          mount_type: MountVolume,
          source: "mysqldata",
          target: "/var/lib/mysql",
          read_only: False,
          options: [],
        ),
      ],
      networks: [],
    )
  is_stateful(container) |> should.equal(True)
}

pub fn is_stateful_data_db_test() {
  let container =
    domain.ContainerSummary(
      id: "c1",
      names: ["storage"],
      image: "myapp:1.0",
      image_id: "",
      command: "app",
      created: 0,
      state: Running,
      status: "running",
      ports: [],
      labels: dict.new(),
      mounts: [
        Mount(
          mount_type: MountVolume,
          source: "vol",
          target: "/data/db",
          read_only: False,
          options: [],
        ),
      ],
      networks: [],
    )
  is_stateful(container) |> should.equal(True)
}

pub fn is_stateful_stateless_test() {
  let container =
    domain.ContainerSummary(
      id: "app1",
      names: ["api"],
      image: "api:1.0",
      image_id: "",
      command: "app",
      created: 0,
      state: Running,
      status: "running",
      ports: [],
      labels: dict.new(),
      mounts: [],
      networks: [],
    )
  is_stateful(container) |> should.equal(False)
}

pub fn is_stateful_no_mounts_test() {
  let container =
    domain.ContainerSummary(
      id: "c2",
      names: ["svc"],
      image: "svc:1",
      image_id: "",
      command: "run",
      created: 0,
      state: Created,
      status: "created",
      ports: [],
      labels: dict.new(),
      mounts: [],
      networks: [],
    )
  is_stateful(container) |> should.equal(False)
}

// ── default_config ────────────────────────────────────────────────────────────

pub fn default_config_api_version_test() {
  let cfg = default_config()
  cfg.api_version |> should.equal("5.7.0")
}

pub fn default_config_timeout_test() {
  let cfg = default_config()
  cfg.timeout_ms |> should.equal(30_000)
}

pub fn default_config_retry_count_test() {
  let cfg = default_config()
  cfg.retry_count |> should.equal(3)
}

pub fn default_config_retry_delay_test() {
  let cfg = default_config()
  cfg.retry_delay_ms |> should.equal(1000)
}

pub fn default_config_socket_rootless_test() {
  let cfg = default_config()
  case cfg.socket {
    Rootless(uid: uid, path: _) -> uid |> should.equal("1000")
    Rootful(_) -> should.fail()
  }
}

pub fn podman_client_config_construction_test() {
  let cfg =
    PodmanClientConfig(
      socket: Rootful(path: "/run/podman/podman.sock"),
      api_version: "4.0.0",
      timeout_ms: 5000,
      retry_count: 1,
      retry_delay_ms: 500,
    )
  cfg.api_version |> should.equal("4.0.0")
  cfg.timeout_ms |> should.equal(5000)
}
