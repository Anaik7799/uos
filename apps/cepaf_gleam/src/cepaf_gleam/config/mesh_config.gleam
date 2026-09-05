//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/config/mesh_config</module>
////     <fsharp-lineage>Cepaf.Config.MeshConfig.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Mesh Configuration &amp; Validation</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-MESH-003</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/order
import gleam/string

// =============================================================================
// Type Definitions
// =============================================================================

/// Specification for a single container in the mesh.
pub type ContainerSpec {
  ContainerSpec(
    name: String,
    image: String,
    port: Int,
    health_check: String,
    cpu_limit: Float,
    memory_mb: Int,
  )
}

/// Network specification for the mesh.
pub type NetworkSpec {
  NetworkSpec(name: String, subnet: String, driver: String)
}

/// Volume specification for persistent storage.
pub type VolumeSpec {
  VolumeSpec(name: String, mount_path: String, size_mb: Int)
}

/// Complete mesh configuration with containers, networks, and volumes.
pub type MeshConfig {
  MeshConfig(
    containers: List(ContainerSpec),
    networks: List(NetworkSpec),
    volumes: List(VolumeSpec),
    quorum_size: Int,
  )
}

/// Validation errors for mesh configuration.
pub type MeshValidationError {
  DuplicatePort(port: Int)
  InvalidSubnet(subnet: String)
  MissingHealthCheck(container: String)
  InsufficientQuorum(required: Int, available: Int)
  ExcessiveResources(message: String)
}

// =============================================================================
// Functions (20)
// =============================================================================

/// Default mesh configuration with 7 core containers.
pub fn default_mesh_config() -> MeshConfig {
  MeshConfig(
    containers: [
      ContainerSpec(
        name: "zenoh-router",
        image: "indrajaal/zenoh:latest",
        port: 7447,
        health_check: "/health",
        cpu_limit: 1.0,
        memory_mb: 512,
      ),
      ContainerSpec(
        name: "gleam-core",
        image: "indrajaal/gleam-core:latest",
        port: 4100,
        health_check: "/api/health",
        cpu_limit: 2.0,
        memory_mb: 1024,
      ),
      ContainerSpec(
        name: "telemetry-collector",
        image: "indrajaal/telemetry:latest",
        port: 4317,
        health_check: "/health",
        cpu_limit: 0.5,
        memory_mb: 256,
      ),
      ContainerSpec(
        name: "immune-system",
        image: "indrajaal/immune:latest",
        port: 4200,
        health_check: "/health",
        cpu_limit: 1.0,
        memory_mb: 512,
      ),
      ContainerSpec(
        name: "knowledge-base",
        image: "indrajaal/knowledge:latest",
        port: 4300,
        health_check: "/health",
        cpu_limit: 1.0,
        memory_mb: 768,
      ),
      ContainerSpec(
        name: "metabolic-engine",
        image: "indrajaal/metabolic:latest",
        port: 4400,
        health_check: "/health",
        cpu_limit: 0.5,
        memory_mb: 256,
      ),
      ContainerSpec(
        name: "substrate-db",
        image: "indrajaal/substrate:latest",
        port: 4500,
        health_check: "/health",
        cpu_limit: 1.0,
        memory_mb: 512,
      ),
    ],
    networks: [
      NetworkSpec(
        name: "indrajaal-mesh",
        subnet: "10.89.0.0/24",
        driver: "bridge",
      ),
    ],
    volumes: [
      VolumeSpec(name: "holon-state", mount_path: "/data/state", size_mb: 1024),
      VolumeSpec(name: "telemetry-logs", mount_path: "/data/logs", size_mb: 512),
    ],
    quorum_size: 4,
  )
}

/// Validate that all container ports are unique.
pub fn validate_unique_ports(config: MeshConfig) -> List(MeshValidationError) {
  config.containers
  |> list.map(fn(c) { c.port })
  |> find_duplicates([])
  |> list.map(fn(p) { DuplicatePort(port: p) })
}

/// Validate that all containers have health checks.
pub fn validate_health_checks(config: MeshConfig) -> List(MeshValidationError) {
  config.containers
  |> list.filter(fn(c) { c.health_check == "" })
  |> list.map(fn(c) { MissingHealthCheck(container: c.name) })
}

/// Run all validations on a mesh configuration.
pub fn validate_all(config: MeshConfig) -> List(MeshValidationError) {
  let port_errors = validate_unique_ports(config)
  let health_errors = validate_health_checks(config)
  let quorum_errors = validate_quorum(config)
  let resource_errors = validate_resources(config)
  list.flatten([port_errors, health_errors, quorum_errors, resource_errors])
}

/// Check if a mesh configuration is valid (no errors).
pub fn is_valid(config: MeshConfig) -> Bool {
  validate_all(config) == []
}

/// Calculate quorum size: floor(n/2) + 1.
pub fn calculate_quorum(n: Int) -> Int {
  n / 2 + 1
}

/// Find a container by name.
pub fn get_container_by_name(
  config: MeshConfig,
  name: String,
) -> Result(ContainerSpec, String) {
  config.containers
  |> list.find(fn(c) { c.name == name })
  |> result_from_option("Container not found: " <> name)
}

/// Get the port for a named container.
pub fn get_container_port(
  config: MeshConfig,
  name: String,
) -> Result(Int, String) {
  case get_container_by_name(config, name) {
    Ok(c) -> Ok(c.port)
    Error(e) -> Error(e)
  }
}

/// Total CPU allocation across all containers.
pub fn total_cpu_allocation(config: MeshConfig) -> Float {
  config.containers
  |> list.fold(0.0, fn(acc, c) { float.add(acc, c.cpu_limit) })
}

/// Total memory allocation across all containers in MB.
pub fn total_memory_allocation(config: MeshConfig) -> Int {
  config.containers
  |> list.fold(0, fn(acc, c) { acc + c.memory_mb })
}

/// Serialize a MeshConfig to JSON.
pub fn config_to_json(config: MeshConfig) -> json.Json {
  json.object([
    #("containers", json.array(config.containers, container_spec_to_json)),
    #("networks", json.array(config.networks, network_spec_to_json)),
    #("volumes", json.array(config.volumes, volume_spec_to_json)),
    #("quorum_size", json.int(config.quorum_size)),
  ])
}

/// Serialize a ContainerSpec to JSON.
pub fn container_spec_to_json(spec: ContainerSpec) -> json.Json {
  json.object([
    #("name", json.string(spec.name)),
    #("image", json.string(spec.image)),
    #("port", json.int(spec.port)),
    #("health_check", json.string(spec.health_check)),
    #("cpu_limit", json.float(spec.cpu_limit)),
    #("memory_mb", json.int(spec.memory_mb)),
  ])
}

/// Serialize a NetworkSpec to JSON.
pub fn network_spec_to_json(spec: NetworkSpec) -> json.Json {
  json.object([
    #("name", json.string(spec.name)),
    #("subnet", json.string(spec.subnet)),
    #("driver", json.string(spec.driver)),
  ])
}

/// Serialize a VolumeSpec to JSON.
pub fn volume_spec_to_json(spec: VolumeSpec) -> json.Json {
  json.object([
    #("name", json.string(spec.name)),
    #("mount_path", json.string(spec.mount_path)),
    #("size_mb", json.int(spec.size_mb)),
  ])
}

/// Print a human-readable summary of the mesh config.
pub fn print_summary(config: MeshConfig) -> String {
  let container_count = list.length(config.containers)
  let total_cpu = total_cpu_allocation(config)
  let total_mem = total_memory_allocation(config)
  string.join(
    [
      "Mesh Configuration Summary",
      "  Containers: " <> int.to_string(container_count),
      "  Networks: " <> int.to_string(list.length(config.networks)),
      "  Volumes: " <> int.to_string(list.length(config.volumes)),
      "  Quorum: " <> int.to_string(config.quorum_size),
      "  Total CPU: " <> float.to_string(total_cpu),
      "  Total Memory: " <> int.to_string(total_mem) <> " MB",
    ],
    with: "\n",
  )
}

/// Get boot stage info string for stage number (1-5).
pub fn get_stage_info(stage: Int) -> String {
  case stage {
    1 -> "Stage 1: Initialize System - Load core modules and verify hardware"
    2 -> "Stage 2: Load Configuration - Parse mesh config and validate"
    3 -> "Stage 3: Mount Filesystems - Attach volumes and verify integrity"
    4 -> "Stage 4: Start Services - Launch containers in dependency order"
    5 -> "Stage 5: Activate Application - Enable routing and health checks"
    _ -> "Unknown stage: " <> int.to_string(stage)
  }
}

/// Add a container to the mesh config.
pub fn add_container(config: MeshConfig, container: ContainerSpec) -> MeshConfig {
  MeshConfig(..config, containers: list.append(config.containers, [container]))
}

/// Remove a container from the mesh config by name.
pub fn remove_container(config: MeshConfig, name: String) -> MeshConfig {
  MeshConfig(
    ..config,
    containers: list.filter(config.containers, fn(c) { c.name != name }),
  )
}

/// Update a container's port by name.
pub fn update_container_port(
  config: MeshConfig,
  name: String,
  new_port: Int,
) -> MeshConfig {
  MeshConfig(
    ..config,
    containers: list.map(config.containers, fn(c) {
      case c.name == name {
        True -> ContainerSpec(..c, port: new_port)
        False -> c
      }
    }),
  )
}

/// Serialize a config summary to JSON (lightweight metadata).
pub fn config_summary_to_json(config: MeshConfig) -> json.Json {
  json.object([
    #("container_count", json.int(list.length(config.containers))),
    #("network_count", json.int(list.length(config.networks))),
    #("volume_count", json.int(list.length(config.volumes))),
    #("quorum_size", json.int(config.quorum_size)),
    #("total_cpu", json.float(total_cpu_allocation(config))),
    #("total_memory_mb", json.int(total_memory_allocation(config))),
    #("is_valid", json.bool(is_valid(config))),
  ])
}

// =============================================================================
// Private helpers
// =============================================================================

fn find_duplicates(ports: List(Int), seen: List(Int)) -> List(Int) {
  case ports {
    [] -> []
    [first, ..rest] ->
      case list.contains(seen, first) {
        True -> [first, ..find_duplicates(rest, seen)]
        False -> find_duplicates(rest, [first, ..seen])
      }
  }
}

fn validate_quorum(config: MeshConfig) -> List(MeshValidationError) {
  let container_count = list.length(config.containers)
  let required = calculate_quorum(container_count)
  case config.quorum_size < required {
    True -> [
      InsufficientQuorum(required: required, available: config.quorum_size),
    ]
    False -> []
  }
}

fn validate_resources(config: MeshConfig) -> List(MeshValidationError) {
  let total_cpu = total_cpu_allocation(config)
  let total_mem = total_memory_allocation(config)
  let cpu_errors = case float.compare(total_cpu, 32.0) {
    order.Gt -> [
      ExcessiveResources(
        message: "Total CPU exceeds 32 cores: " <> float.to_string(total_cpu),
      ),
    ]
    _ -> []
  }
  let mem_errors = case total_mem > 65_536 {
    True -> [
      ExcessiveResources(
        message: "Total memory exceeds 64GB: "
        <> int.to_string(total_mem)
        <> "MB",
      ),
    ]
    False -> []
  }
  list.append(cpu_errors, mem_errors)
}

fn result_from_option(
  opt: Result(a, Nil),
  error_msg: String,
) -> Result(a, String) {
  case opt {
    Ok(v) -> Ok(v)
    Error(_) -> Error(error_msg)
  }
}
