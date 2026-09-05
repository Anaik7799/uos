//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/podman/http_client</module>
////     <fsharp-lineage>Cepaf.Podman.Client.UnixSocket.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Podman UDS Orchestration</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MESH-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="clr-socket">
////       F# `UnixDomainSocketEndPoint` ↠ Erlang `hackney` via NIF.
////       Mitigation: Socket errors are flattened to strings inside Erlang FFI, caught by Result pattern matching.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/podman/domain.{type PodmanClientConfig, Rootful, Rootless}
import gleam/http.{type Method}
import gleam/http/response

pub type PodmanClient {
  PodmanClient(
    config: PodmanClientConfig,
    socket_path: String,
    base_path: String,
  )
}

pub fn create(config: PodmanClientConfig) -> PodmanClient {
  let socket_path = case config.socket {
    Rootful(path) -> path
    Rootless(_uid, path) -> path
  }
  let base_path = "http://localhost/v" <> config.api_version <> "/libpod"
  PodmanClient(config: config, socket_path: socket_path, base_path: base_path)
}

@external(erlang, "cepaf_gleam_ffi", "hackney_request")
fn hackney_request(
  method: Method,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
  socket_path: String,
) -> Result(#(Int, List(#(String, String)), BitArray), String)

pub fn send_request(
  client: PodmanClient,
  method: Method,
  endpoint: String,
  body: BitArray,
) -> Result(response.Response(BitArray), String) {
  let url = client.base_path <> endpoint
  let headers = [
    #("host", "localhost"),
    #("content-type", "application/json"),
  ]

  case hackney_request(method, url, headers, body, client.socket_path) {
    Ok(#(status, resp_headers, resp_body)) ->
      Ok(response.Response(
        status: status,
        headers: resp_headers,
        body: resp_body,
      ))
    Error(e) -> Error(e)
  }
}

pub fn get(
  client: PodmanClient,
  endpoint: String,
) -> Result(response.Response(BitArray), String) {
  send_request(client, http.Get, endpoint, <<>>)
}

pub fn post(
  client: PodmanClient,
  endpoint: String,
  body: BitArray,
) -> Result(response.Response(BitArray), String) {
  send_request(client, http.Post, endpoint, body)
}
