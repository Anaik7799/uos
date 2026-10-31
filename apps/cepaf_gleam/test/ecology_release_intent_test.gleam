import cepaf_gleam/ecology/release_intent as i
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub const host = "nas-1.tail55d152.ts.net"

pub const boot = "private-fixture-boot"

pub const clock_domain = "private-fixture-vm-1"

pub fn dg(c: String) -> String {
  "sha256:" <> string.repeat(c, 64)
}

pub fn proposal() -> i.Proposal {
  i.Proposal(
    i.Digests(
      dg("a"),
      dg("b"),
      dg("c"),
      dg("d"),
      dg("e"),
      dg("f"),
      dg("1"),
      dg("2"),
      dg("3"),
      dg("4"),
    ),
    i.Execution(
      "/private/review-workspace",
      "uos/release",
      "OI02E",
      "private-worker",
      1,
    ),
    host,
    boot,
    clock_domain,
    "runtime:ecology",
    7,
    "private-fixture-nonce",
    i.Window(1_000_000, 1_060_000, -80_000, -20_000),
  )
}

pub fn intent() -> i.Intent {
  let assert Ok(x) = i.new(proposal())
  x
}

pub fn all_semantic_fields_change_digest_test() {
  let p = proposal()
  let d = p.digests
  let e = p.execution
  let w = p.window
  let changed = [
    i.Proposal(..p, digests: i.Digests(..d, transaction_id: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, candidate: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, payload: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, source: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, previous_candidate: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, previous_payload: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, physical_manifest: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, native_artifact: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, runtime_evidence: dg("5"))),
    i.Proposal(..p, digests: i.Digests(..d, formal_evidence: dg("5"))),
    i.Proposal(..p, execution: i.Execution(..e, workspace: "/private/other")),
    i.Proposal(..p, execution: i.Execution(..e, plan: "other")),
    i.Proposal(..p, execution: i.Execution(..e, task: "other")),
    i.Proposal(..p, execution: i.Execution(..e, worker: "other")),
    i.Proposal(..p, execution: i.Execution(..e, attempt: 2)),
    i.Proposal(..p, host: "vm-1.tail55d152.ts.net"),
    i.Proposal(..p, boot: "other"),
    i.Proposal(..p, clock_domain: "different-vm-same-linux-boot"),
    i.Proposal(..p, runtime_resource: "runtime:other"),
    i.Proposal(..p, runtime_epoch: 8),
    i.Proposal(..p, nonce: "other"),
    i.Proposal(..p, window: i.Window(..w, created_utc_ms: 999_999)),
    i.Proposal(..p, window: i.Window(..w, expires_utc_ms: 1_059_999)),
    i.Proposal(..p, window: i.Window(..w, created_mono_ms: -80_001)),
    i.Proposal(..p, window: i.Window(..w, expires_mono_ms: -20_001)),
  ]
  list.each(changed, fn(p) {
    let assert Ok(x) = i.new(p)
    { i.digest(x) != i.digest(intent()) } |> should.be_true
  })
}

pub fn strict_clock_domain_and_boot_identity_test() {
  let x = intent()
  i.valid_at(x, host, boot, clock_domain, 1_000_000, -80_000) |> should.be_true
  i.valid_at(x, host, boot, clock_domain, 1_030_000, -50_000) |> should.be_true
  list.each(
    [
      #(999_999, -50_000),
      #(1_060_000, -50_000),
      #(1_030_000, -80_001),
      #(1_030_000, -20_000),
      #(-1, -50_000),
    ],
    fn(t) {
      i.valid_at(x, host, boot, clock_domain, t.0, t.1) |> should.be_false
    },
  )
  i.valid_at(
    x,
    "vm-1.tail55d152.ts.net",
    boot,
    clock_domain,
    1_030_000,
    -50_000,
  )
  |> should.be_false
  i.valid_at(x, host, "rebooted", clock_domain, 1_030_000, -50_000)
  |> should.be_false
}

pub fn invalid_proposals_fail_closed_test() {
  let p = proposal()
  list.each(
    [
      i.Proposal(
        ..p,
        digests: i.Digests(..p.digests, source: "source-label-is-not-sha256"),
      ),
      i.Proposal(..p, digests: i.Digests(..p.digests, candidate: dg("G"))),
      i.Proposal(
        ..p,
        execution: i.Execution(..p.execution, workspace: "/private/../escape"),
      ),
      i.Proposal(
        ..p,
        execution: i.Execution(..p.execution, workspace: "relative"),
      ),
      i.Proposal(..p, execution: i.Execution(..p.execution, attempt: 0)),
      i.Proposal(
        ..p,
        execution: i.Execution(..p.execution, worker: string.repeat("x", 257)),
      ),
      i.Proposal(..p, host: "nas-1.local"),
      i.Proposal(..p, host: "NAS-1.tail55d152.ts.net"),
      i.Proposal(..p, runtime_resource: "integration/main"),
      i.Proposal(..p, runtime_resource: "runtime:x/y"),
      i.Proposal(..p, runtime_epoch: 0),
      i.Proposal(..p, nonce: "bad\u{0000}"),
      i.Proposal(..p, window: i.Window(1, 3_600_002, 0, 1000)),
      i.Proposal(..p, window: i.Window(0, 1000, -1, 3_600_000)),
      i.Proposal(..p, window: i.Window(100, 100, -100, -99)),
      i.Proposal(
        ..p,
        window: i.Window(0, 100, -9_000_000_000_000_001, -9_000_000_000_000_000),
      ),
    ],
    fn(p) { i.new(p) |> result.is_error |> should.be_true },
  )
}

pub fn canonical_accessors_and_no_admission_claim_test() {
  let x = intent()
  { i.canonical_json(x) == i.canonical_json(intent()) } |> should.be_true
  string.contains(i.canonical_json(x), i.domain) |> should.be_true
  string.contains(i.canonical_json(x), "application_admitted")
  |> should.be_false
  i.bindings(x) |> should.equal(proposal().digests)
  i.execution(x) |> should.equal(proposal().execution)
  i.transaction_id(x) |> should.equal(dg("a"))
  i.candidate(x) |> should.equal(dg("b"))
  i.manifest(x) |> should.equal(dg("1"))
  i.runtime_resource(x) |> should.equal("runtime:ecology")
  i.expires_mono_ms(x) |> should.equal(-20_000)
}

pub fn same_host_boot_different_vm_origin_is_not_the_same_clock_test() {
  i.valid_at(
    intent(),
    host,
    boot,
    "different-vm-same-linux-boot",
    1_030_000,
    -50_000,
  )
  |> should.be_false
  let p = proposal()
  let assert Ok(low) =
    i.new(
      i.Proposal(
        ..p,
        window: i.Window(
          0,
          1000,
          -9_000_000_000_000_000,
          -8_999_999_999_999_000,
        ),
      ),
    )
  i.valid_at(low, host, boot, clock_domain, 0, -9_000_000_000_000_000)
  |> should.be_true
  i.valid_at(low, host, boot, clock_domain, 999, -8_999_999_999_999_000)
  |> should.be_false
}
