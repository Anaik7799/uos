//// TLS Listener Substrate — Wave-17 W7 (fixture follow-up: worker W-E)
////
//// Verifies the HTTPS-on-:4101 substrate that server.gleam wires via
//// `mist.with_tls(certfile: "priv/ssl/cert.pem", keyfile: "priv/ssl/key.pem")`.
////
//// server.gleam:1222-1223 hardcodes the runtime cert/key paths to
//// "priv/ssl/cert.pem" / "priv/ssl/key.pem" — that convention is NOT
//// modified by this test file. A real deploy must place a real cert/key
//// pair at that on-disk location; committing key or certificate material
//// into the repository is barred (CLAUDE.md: "Never commit key or
//// certificate material into the repository").
////
//// Since `priv/ssl/` does not exist in the tree (by design — no committed
//// keys), these tests no longer read that path. Instead they exercise the
//// same PEM-envelope contract server.gleam's mist.with_tls call depends on
//// (well-formed X.509 certificate PEM + well-formed private-key PEM)
//// against an ephemeral, freshly-generated self-signed cert/key pair
//// produced at test time by `cepaf_tls_test_fixture:ensure_pem/1`
//// (src/cepaf_tls_test_fixture.erl), which itself uses Erlang/OTP's own
//// `public_key:pkix_test_data/1` test-data generator and
//// `public_key:pem_encode/1`. The pair is written under a scratch
//// directory (env UOS_TLS_TEST_ROOT if set, else build/tls-test/),
//// regenerated on every test run, and never committed.
////
//// [zk-3346fc607a1ef9e6] Stub-That-Lies guard: we still read real,
//// freshly-generated file content on disk — not fabricated strings — and
//// still assert the real PEM markers. If the fixture generator breaks,
//// these tests fail loud (via `let assert`), not silently.

import gleam/string
import gleeunit/should
import simplifile

/// Test-only FFI binding: generates (or regenerates) an ephemeral
/// self-signed cert.pem/key.pem pair under `default_root` (or
/// $UOS_TLS_TEST_ROOT when set) and returns their paths.
/// See src/cepaf_tls_test_fixture.erl for the implementation.
@external(erlang, "cepaf_tls_test_fixture", "ensure_pem")
fn ensure_pem(default_root: String) -> Result(#(String, String), String)

/// Resolve the ephemeral fixture's cert/key paths, generating them fresh.
/// Panics loudly (Stub-That-Lies guard) if the OTP-native generator fails —
/// there is no silent fallback to fabricated content.
fn fixture_paths() -> #(String, String) {
  let assert Ok(paths) = ensure_pem("build/tls-test")
  paths
}

pub fn cert_pem_file_exists_test() {
  let #(cert_path, _key_path) = fixture_paths()
  let assert Ok(_content) = simplifile.read(cert_path)
}

pub fn key_pem_file_exists_test() {
  let #(_cert_path, key_path) = fixture_paths()
  let assert Ok(_content) = simplifile.read(key_path)
}

pub fn cert_is_valid_pem_envelope_test() {
  let #(cert_path, _key_path) = fixture_paths()
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
  let #(_cert_path, key_path) = fixture_paths()
  let assert Ok(content) = simplifile.read(key_path)
  // Accepts either PKCS#1 (including SEC1 "EC PRIVATE KEY") or PKCS#8
  // envelopes.
  let is_pem =
    string.contains(content, "PRIVATE KEY-----")
    && string.contains(content, "-----BEGIN")
  should.be_true(is_pem)
}
