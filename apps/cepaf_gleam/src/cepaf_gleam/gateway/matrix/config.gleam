//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/config</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-006</stamp-controls></compliance>
//// </c3i-module>
////
//// tuwunel container configuration + mesh integration.

import gleam/int

pub type TuwunelConfig {
  TuwunelConfig(
    server_name: String,
    database_path: String,
    port: Int,
    max_request_size_mb: Int,
    allow_registration: Bool,
    allow_federation: Bool,
    trusted_servers: List(String),
    log_level: String,
    address: String,
  )
}

pub type MatrixContainerSpec {
  MatrixContainerSpec(
    name: String,
    image: String,
    federation_port: Int,
    client_port: Int,
    cpu_limit: Float,
    memory_mb: Int,
    health_endpoint: String,
    volume_path: String,
    boot_tier: Int,
  )
}

pub fn default_config(server_name: String) -> TuwunelConfig {
  TuwunelConfig(
    server_name: server_name,
    database_path: "/var/lib/tuwunel",
    port: 6167,
    max_request_size_mb: 20,
    allow_registration: False,
    allow_federation: True,
    trusted_servers: ["matrix.org"],
    log_level: "info",
    address: "0.0.0.0",
  )
}

pub fn container_spec() -> MatrixContainerSpec {
  MatrixContainerSpec(
    name: "matrix-homeserver",
    image: "ghcr.io/matrix-construct/tuwunel:latest",
    federation_port: 8448,
    client_port: 6167,
    cpu_limit: 1.0,
    memory_mb: 512,
    health_endpoint: "/_matrix/client/versions",
    volume_path: "/var/lib/tuwunel",
    boot_tier: 5,
  )
}

pub fn health_check_url(spec: MatrixContainerSpec) -> String {
  "http://localhost:" <> int.to_string(spec.client_port) <> spec.health_endpoint
}

pub fn is_port_safe(port: Int) -> Bool {
  // Ports 4000-4010 are reserved for the SIL-6 mesh
  port < 4000 || port > 4010
}

pub fn volume_name() -> String {
  "matrix-data"
}

pub fn config_to_toml(config: TuwunelConfig) -> String {
  "[global]\n"
  <> "server_name = \""
  <> config.server_name
  <> "\"\n"
  <> "database_path = \""
  <> config.database_path
  <> "\"\n"
  <> "port = "
  <> int.to_string(config.port)
  <> "\n"
  <> "max_request_size = "
  <> int.to_string(config.max_request_size_mb * 1_000_000)
  <> "\n"
  <> "allow_registration = "
  <> bool_to_toml(config.allow_registration)
  <> "\n"
  <> "allow_federation = "
  <> bool_to_toml(config.allow_federation)
  <> "\n"
  <> "address = \""
  <> config.address
  <> "\"\n"
  <> "log = \""
  <> config.log_level
  <> "\"\n"
  <> "\n[global.well_known]\n"
  <> "server = \""
  <> config.server_name
  <> ":8448\"\n"
  <> "client = \"https://"
  <> config.server_name
  <> "\"\n"
}

pub fn environment_vars(config: TuwunelConfig) -> List(#(String, String)) {
  [
    #("TUWUNEL_SERVER_NAME", config.server_name),
    #("TUWUNEL_DATABASE_PATH", config.database_path),
    #("TUWUNEL_PORT", int.to_string(config.port)),
    #("TUWUNEL_LOG", config.log_level),
    #("TUWUNEL_ALLOW_REGISTRATION", bool_to_toml(config.allow_registration)),
    #("TUWUNEL_ALLOW_FEDERATION", bool_to_toml(config.allow_federation)),
  ]
}

pub fn summary(spec: MatrixContainerSpec) -> String {
  spec.name
  <> " ("
  <> spec.image
  <> ") ports="
  <> int.to_string(spec.federation_port)
  <> "/"
  <> int.to_string(spec.client_port)
  <> " tier="
  <> int.to_string(spec.boot_tier)
  <> " mem="
  <> int.to_string(spec.memory_mb)
  <> "MB"
}

fn bool_to_toml(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
