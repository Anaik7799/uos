---
name: cepaf-podman-expert
description: Domain-specific expert for Podman container orchestration within CEPAF. Use when porting F# Podman logic to Gleam, interacting with the Podman REST API over UDS, or managing container lifecycles in the SIL-6 mesh.
---
# CEPAF Podman Expert Skill
This skill provides deep domain knowledge for managing Podman resources (Containers, Pods, Networks, Volumes) using the Podman REST API.
# Core Mandates
1.  **UDS Exclusivity**: ALWAYS communicate with Podman via the Unix Domain Socket (UDS). Default paths:
- Rootless: `/run/user/{UID}/podman/podman.sock`
- Rootful: `/run/podman/podman.sock`
2.  **API Version Alignment**: Target Podman API version `5.7.0` as the baseline.
3.  **Type-Safe Orchestration**: Port F# domain types to strongly-typed Gleam equivalents to prevent structural drift.
4.  **Health-First Lifecycle**: Every container operation MUST be verified by a corresponding health probe or `inspect` call.
# API Schema Reference
# List Containers
- **Endpoint**: `GET /v{version}/libpod/containers/json`
- **Query Params**: `all=true` to include non-running containers.
- **Response**: List of `ContainerSummary` (Mapping: `Names` -> `List(String)`, `State` -> `String/Enum`).
# Inspect Container
- **Endpoint**: `GET /v{version}/libpod/containers/{name_or_id}/json`
- **Response**: Full `ContainerInspect` object. Critical fields: `State.Health`, `NetworkSettings.IPAddress`.
# Start/Stop
- **Start**: `POST /v{version}/libpod/containers/{name_or_id}/start`
- **Stop**: `POST /v{version}/libpod/containers/{name_or_id}/stop?t=10` (t is timeout in seconds).
# Gleam Integration Patterns
Use the `cepaf_gleam/podman/http_client` and `containers` modules for all interactions.
```gleam
import cepaf_gleam/podman/containers
import cepaf_gleam/podman/http_client
// Example: Force restarting a container
pub fn force_restart(client: http_client.PodmanClient, name: String) {
use _ <- result.try(http_client.post(client, "/containers/" <> name <> "/stop", <<>>))
http_client.post(client, "/containers/" <> name <> "/start", <<>>)
}
```
# Troubleshooting
- **badarg**: Check Erlang FFI argument types (ensure strings are binaries).
- **ENOENT**: Verify the `UID` environment variable and ensure the Podman socket exists at the detected path.
- **JSON Decode Error**: Verify the Podman API version matches the expected schema.