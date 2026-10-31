import cepaf_gleam/ecology/release_identity as identity
import gleam/json
import gleam/list
import gleam/result
import gleeunit/should

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

const issuer = "https://nas-1.tail55d152.ts.net:4101/realms/uos"

const audience = "uos-release-control"

const now = 2_000_000_000_000

const mono = -5000

fn configuration(role, acr, life) {
  let keys =
    json.object([
      #(
        "keys",
        json.array(
          [
            json.object([
              #("kty", json.string("OKP")),
              #("crv", json.string("Ed25519")),
              #("kid", json.string("operator-key")),
              #("alg", json.string("EdDSA")),
              #("x", json.string(public_key("operator"))),
            ]),
          ],
          fn(x) { x },
        ),
      ),
    ])
    |> json.to_string
  identity.configure(issuer, audience, keys, now, 300_000, role, acr, life)
}

fn token(overrides: List(#(String, json.Json))) -> String {
  let fields = [
    #("sub", json.string("operator-123")),
    #("iss", json.string(issuer)),
    #("aud", json.string(audience)),
    #("iat", json.int(now / 1000)),
    #("nbf", json.int(now / 1000)),
    #("exp", json.int(now / 1000 + 3600)),
    #(
      "realm_access",
      json.object([#("roles", json.array(["uos-release-client"], json.string))]),
    ),
    #("acr", json.string("urn:uos:mfa")),
  ]
  let changed =
    list.map(fields, fn(pair) {
      case list.find(overrides, fn(o) { o.0 == pair.0 }) {
        Ok(v) -> v
        Error(_) -> pair
      }
    })
  sign("operator", json.object(changed) |> json.to_string)
}

pub fn actual_crypto_identity_and_negative_monotonic_clock_test() {
  let assert Ok(config) =
    configuration("uos-release-client", ["urn:uos:mfa"], 10_000)
  let assert Ok(proof) =
    identity.authenticate(config, token([]), "nas", "boot-a", "vm-a", now, mono)
  identity.subject(proof) |> should.equal("operator-123")
  identity.still_valid(
    config,
    proof,
    "nas",
    "boot-a",
    "vm-a",
    now + 1,
    mono + 1,
  )
  |> should.be_true
  identity.still_valid(
    config,
    proof,
    "nas",
    "boot-a",
    "vm-a",
    now + 10_000,
    mono + 10_000,
  )
  |> should.be_false
}

pub fn exact_signed_role_and_acr_are_required_test() {
  let assert Ok(config) =
    configuration("uos-release-client", ["urn:uos:mfa"], 10_000)
  list.each(
    [
      [
        #(
          "realm_access",
          json.object([
            #("roles", json.array(["uos-release-client-admin"], json.string)),
          ]),
        ),
      ],
      [#("acr", json.string("not-urn:uos:mfa"))],
      [#("sub", json.string(""))],
      [#("iss", json.string("https://vm-1.tail55d152.ts.net:4101"))],
      [#("aud", json.string("other-purpose"))],
    ],
    fn(changes) {
      identity.authenticate(
        config,
        token(changes),
        "nas",
        "boot-a",
        "vm-a",
        now,
        mono,
      )
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn no_skew_grace_for_privileged_identity_test() {
  let assert Ok(config) =
    configuration("uos-release-client", ["urn:uos:mfa"], 10_000)
  list.each(
    [
      [#("exp", json.int(now / 1000))],
      [#("iat", json.int(now / 1000 + 1))],
      [#("nbf", json.int(now / 1000 + 1))],
    ],
    fn(changes) {
      identity.authenticate(
        config,
        token(changes),
        "nas",
        "boot-a",
        "vm-a",
        now,
        mono,
      )
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn vm_boot_host_clock_rollback_and_key_freshness_test() {
  let assert Ok(config) =
    configuration("uos-release-client", ["urn:uos:mfa"], 10_000)
  let assert Ok(proof) =
    identity.authenticate(config, token([]), "nas", "boot-a", "vm-a", now, mono)
  identity.still_valid(
    config,
    proof,
    "nas",
    "boot-a",
    "vm-b",
    now + 1,
    mono + 1,
  )
  |> should.be_false
  identity.still_valid(
    config,
    proof,
    "nas",
    "boot-b",
    "vm-a",
    now + 1,
    mono + 1,
  )
  |> should.be_false
  identity.still_valid(
    config,
    proof,
    "other",
    "boot-a",
    "vm-a",
    now + 1,
    mono + 1,
  )
  |> should.be_false
  identity.still_valid(
    config,
    proof,
    "nas",
    "boot-a",
    "vm-a",
    now - 1,
    mono + 1,
  )
  |> should.be_false
  identity.still_valid(
    config,
    proof,
    "nas",
    "boot-a",
    "vm-a",
    now + 1,
    mono - 1,
  )
  |> should.be_false
  identity.authenticate(
    config,
    token([]),
    "nas",
    "boot-a",
    "vm-a",
    now + 300_000,
    mono + 1,
  )
  |> result.is_error
  |> should.be_true
}

pub fn explicit_safe_configuration_and_tailnet_issuer_test() {
  list.each(
    [
      "http://nas-1.tail55d152.ts.net:4101",
      "https://nas-1.tail55d152.ts.net.evil/",
      "https://user@nas-1.tail55d152.ts.net",
      "https://nas-1.tail55d152.ts.net:0",
      "https://nas-1.tail55d152.ts.net:04101",
      "https://nas-1.tail55d152.ts.net?issuer=x",
      "https://.tail55d152.ts.net",
      "https://foo.bar.tail55d152.ts.net",
      "https://-nas.tail55d152.ts.net",
      "https://nas-.tail55d152.ts.net",
      "https://nas-1.tail55d152.ts.net/realm\nother",
      "https://nas-1.tail55d152.ts.net/realm other",
      "https://nas-1.tail55d152.ts.net/realm\\other",
      "https://nas-1.tail55d152.ts.net/realm\u{007f}other",
    ],
    fn(url) { identity.tailnet_issuer(url) |> should.be_false },
  )
  configuration("", ["urn:uos:mfa"], 10_000)
  |> result.is_error
  |> should.be_true
  configuration("uos-release-client", [], 10_000)
  |> result.is_error
  |> should.be_true
  configuration("uos-release-client", ["urn:uos:mfa"], 30_001)
  |> result.is_error
  |> should.be_true
}
