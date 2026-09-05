import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/string

// ============================================================================
// Container Types
// ============================================================================

pub type ContainerStatus {
  Created
  Running
  Paused
  Restarting
  Removing
  Exited(exit_code: Int)
  Dead(reason: String)
  Unknown(status: String)
}

pub fn status_to_string(status: ContainerStatus) -> String {
  case status {
    Created -> "created"
    Running -> "running"
    Paused -> "paused"
    Restarting -> "restarting"
    Removing -> "removing"
    Exited(_) -> "exited"
    Dead(_) -> "dead"
    Unknown(s) -> s
  }
}

pub fn string_to_status(status: String) -> ContainerStatus {
  case status {
    "created" -> Created
    "running" -> Running
    "paused" -> Paused
    "restarting" -> Restarting
    "removing" -> Removing
    "exited" -> Exited(0)
    "dead" -> Dead("unknown")
    s -> Unknown(s)
  }
}

pub type HealthStatus {
  Starting
  Healthy
  Unhealthy(failing_streak: Int)
  NoHealthcheck
  UnknownHealth(status: String)
}

pub fn health_status_to_string(status: HealthStatus) -> String {
  case status {
    Starting -> "starting"
    Healthy -> "healthy"
    Unhealthy(_) -> "unhealthy"
    NoHealthcheck -> "none"
    UnknownHealth(s) -> s
  }
}

pub fn string_to_health_status(status: String) -> HealthStatus {
  case status {
    "starting" -> Starting
    "healthy" -> Healthy
    "unhealthy" -> Unhealthy(0)
    "none" | "" -> NoHealthcheck
    s -> UnknownHealth(s)
  }
}

pub type PortProtocol {
  Tcp
  Udp
  Sctp
}

pub type PortMapping {
  PortMapping(
    container_port: Int,
    host_port: Option(Int),
    host_ip: Option(String),
    protocol: PortProtocol,
    range: Option(Int),
  )
}

pub type MountType {
  Bind
  MountVolume
  Tmpfs
  Image
  Devpts
}

pub type Mount {
  Mount(
    mount_type: MountType,
    source: String,
    target: String,
    read_only: Bool,
    options: List(String),
  )
}

pub type ContainerSummary {
  ContainerSummary(
    id: String,
    names: List(String),
    image: String,
    image_id: String,
    command: String,
    created: Int,
    // Unix timestamp
    state: ContainerStatus,
    status: String,
    ports: List(PortMapping),
    labels: Dict(String, String),
    mounts: List(Mount),
    networks: List(String),
  )
}

/// Determine if a container is stateful based on its mounts.
/// SC-LIFECYCLE-001: Stateful containers must not be force-removed.
/// A container is stateful if it has a mount targeting PostgreSQL data,
/// MySQL data, or other persistent storage directories.
pub fn is_stateful(container: ContainerSummary) -> Bool {
  list.any(container.mounts, fn(m) {
    string.contains(m.target, "postgresql")
    || string.contains(m.target, "mysql")
    || string.contains(m.target, "/data/db")
  })
}

pub type HealthCheckLog {
  HealthCheckLog(start: String, end: String, exit_code: Int, output: String)
}

pub type HealthCheckResult {
  HealthCheckResult(
    status: HealthStatus,
    failing_streak: Int,
    log: List(HealthCheckLog),
  )
}

pub type ContainerStateDetail {
  ContainerStateDetail(
    status: ContainerStatus,
    running: Bool,
    paused: Bool,
    restarting: Bool,
    oom_killed: Bool,
    dead: Bool,
    pid: Int,
    exit_code: Int,
    error: String,
    started_at: String,
    finished_at: String,
    health: Option(HealthCheckResult),
  )
}

pub type ContainerInspect {
  ContainerInspect(
    id: String,
    created: String,
    path: String,
    args: List(String),
    state: ContainerStateDetail,
    image: String,
    image_name: String,
    name: String,
    restart_count: Int,
    platform: String,
    mount_label: String,
    process_label: String,
    mounts: List(Mount),
    labels: Dict(String, String),
    env: List(String),
  )
}

// ============================================================================
// Volume Types
// ============================================================================

pub type Volume {
  Volume(
    name: String,
    driver: String,
    mountpoint: String,
    created_at: String,
    labels: Dict(String, String),
    options: Dict(String, String),
    scope: String,
  )
}

pub type VolumeSpec {
  VolumeSpec(
    name: String,
    driver: String,
    labels: Dict(String, String),
    options: Dict(String, String),
  )
}

// ============================================================================
// Network Types
// ============================================================================

pub type Subnet {
  Subnet(subnet: String, gateway: Option(String))
}

pub type Network {
  Network(
    name: String,
    id: String,
    driver: String,
    created: String,
    subnets: List(Subnet),
    internal: Bool,
    dns_enabled: Bool,
    labels: Dict(String, String),
    options: Dict(String, String),
  )
}

pub type NetworkSpec {
  NetworkSpec(
    name: String,
    driver: String,
    internal: Bool,
    dns_enabled: Bool,
    subnets: List(Subnet),
    labels: Dict(String, String),
    options: Dict(String, String),
  )
}

// ============================================================================
// Client Configuration
// ============================================================================

pub type PodmanSocket {
  Rootful(path: String)
  Rootless(uid: String, path: String)
}

pub type PodmanClientConfig {
  PodmanClientConfig(
    socket: PodmanSocket,
    api_version: String,
    timeout_ms: Int,
    retry_count: Int,
    retry_delay_ms: Int,
  )
}

pub fn default_config() -> PodmanClientConfig {
  PodmanClientConfig(
    socket: Rootless(uid: "1000", path: "/run/user/1000/podman/podman.sock"),
    api_version: "5.7.0",
    timeout_ms: 30_000,
    retry_count: 3,
    retry_delay_ms: 1000,
  )
}
