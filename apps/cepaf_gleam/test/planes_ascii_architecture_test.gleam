//// =============================================================================
//// [C3I-SIL6-PLANES-ASCII-TEST] TRI-PLANE ASCII ARCHITECTURE VERIFICATION TEST
//// =============================================================================

import cepaf_gleam/sdlc/planes_ascii_architecture.{
  all_planes_ascii, control_plane_ascii, data_plane_ascii, encode_planes_json,
  verification_plane_ascii,
}
import gleam/string
import gleeunit/should

pub fn control_plane_ascii_content_test() {
  let ascii = control_plane_ascii()

  string.contains(ascii, "CONTROL PLANE ARCHITECTURE") |> should.be_true
  string.contains(ascii, "OTP 29 ROOT 4-DOMAIN SUPERVISOR") |> should.be_true
  string.contains(ascii, "2oo3 CONSTITUTIONAL QUORUM") |> should.be_true
  string.contains(ascii, "HARDWARE STORAGE INTERLOCK") |> should.be_true
  string.contains(ascii, "25503L801736") |> should.be_true
  string.contains(ascii, "14 FRACTAL ASPECT ACTIVE PROCESSING AGENTS")
  |> should.be_true
  string.contains(ascii, "LYAPUNOV WINDOWED DRIFT") |> should.be_true
}

pub fn data_plane_ascii_content_test() {
  let ascii = data_plane_ascii()

  string.contains(ascii, "DATA PLANE ARCHITECTURE") |> should.be_true
  string.contains(ascii, "ZERO-MUDA DESCRIPTOR-RELATIVE HIGH-THROUGHPUT VFS")
  |> should.be_true
  string.contains(ascii, "ZigVM") |> should.be_true
  string.contains(ascii, "Zenoh ZMOF") |> should.be_true
  string.contains(ascii, "SQLITE WAL APPEND-ONLY TRANSACTION LOG")
  |> should.be_true
  string.contains(ascii, "MODULAR MAX / MOJO INFERENCE PIPE") |> should.be_true
  string.contains(ascii, "TRIPLE-INTERFACE PRESENTATION SURFACES")
  |> should.be_true
}

pub fn verification_plane_ascii_content_test() {
  let ascii = verification_plane_ascii()

  string.contains(ascii, "VERIFICATION PLANE ARCHITECTURE") |> should.be_true
  string.contains(ascii, "LEAN 4 THEOREM PROVER") |> should.be_true
  string.contains(ascii, "QUINT FORMAL MODEL") |> should.be_true
  string.contains(ascii, "HERMES GOSPEL & Z3") |> should.be_true
  string.contains(ascii, "ZERO-TRUST MCP DISPATCH INTERCEPTOR")
  |> should.be_true
  string.contains(ascii, "CAPABILITY STATE POSET LATTICE") |> should.be_true
  string.contains(ascii, "9-DIMENSION TEST PROTOCOL") |> should.be_true
  string.contains(ascii, "4 MATHEMATICAL QUALITY GATES") |> should.be_true
  string.contains(ascii, "PRODUCTION CONJUNCTION") |> should.be_true
}

pub fn all_planes_ascii_test() {
  let all_ascii = all_planes_ascii()

  string.contains(all_ascii, "CONTROL PLANE ARCHITECTURE") |> should.be_true
  string.contains(all_ascii, "DATA PLANE ARCHITECTURE") |> should.be_true
  string.contains(all_ascii, "VERIFICATION PLANE ARCHITECTURE")
  |> should.be_true
}

pub fn encode_planes_json_test() {
  let json_str = encode_planes_json()

  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true
  string.contains(json_str, "\"control_plane\"") |> should.be_true
  string.contains(json_str, "\"data_plane\"") |> should.be_true
  string.contains(json_str, "\"verification_plane\"") |> should.be_true
}
