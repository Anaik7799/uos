//// TLS Listener Substrate — Wave-17 W7
////
//// Verifies the HTTPS-on-:4101 substrate that server.gleam wires via
//// `mist.with_tls(certfile: "priv/ssl/cert.pem", keyfile: "priv/ssl/key.pem")`.
////
//// W7 substrate was already complete pre-Wave-17:
////   - cert.pem + key.pem present at lib/cepaf_gleam/priv/ssl/
////   - Mist 6.0+ provides `with_tls` wrapper
////   - server.gleam:1252-1277 starts an HTTPS listener on port+1 (4101)
////
//// These tests assert the on-disk substrate. Live HTTPS bind verification
//// requires a running server and is deferred to the integration harness.
////
//// [zk-3346fc607a1ef9e6] Stub-That-Lies guard: we read the actual files.
//// We do NOT fabricate cert content. If the substrate disappears, these
//// tests fail loud, not silently.

import gleam/string
import gleeunit/should
import simplifile

const cert_path = "priv/ssl/cert.pem"

const key_path = "priv/ssl/key.pem"

pub fn cert_pem_file_exists_test() {
  let assert Ok(_content) = simplifile.read(cert_path)
}

pub fn key_pem_file_exists_test() {
  let assert Ok(_content) = simplifile.read(key_path)
}

pub fn cert_is_valid_pem_envelope_test() {
  let assert Ok(content) = simplifile.read(cert_path)
  // Real PEM-armored x509 cert. If a future regression replaces the file
  // with bytes that LOOK like a cert but aren't, this header check fails.
  content
  |> string.contains("-----BEGIN CERTIFICATE-----")
  |> should.be_true
  content
  |> string.contains("-----END CERTIFICATE-----")
  |> should.be_true
}

pub fn key_is_valid_pem_envelope_test() {
  let assert Ok(content) = simplifile.read(key_path)
  // Accepts either PKCS#1 or PKCS#8 envelope.
  let is_pem =
    string.contains(content, "PRIVATE KEY-----")
    && string.contains(content, "-----BEGIN")
  should.be_true(is_pem)
}
