//// Release-authority PREPARATION profile. An Intent binds supplied identifiers
//// and digests, not the truth/existence of runtime or formal evidence. No IO,
//// grant, signing key, admission or effect is created by this module.

import cepaf_gleam/harness/files
import gleam/json
import gleam/list
import gleam/string

pub const domain = "uos.ecology.cutover.intent.v1"

pub const approval_purpose = "uos.ecology.cutover.approval.v1"

pub const maximum_window_ms = 3_600_000

pub type Execution {
  Execution(
    workspace: String,
    plan: String,
    task: String,
    worker: String,
    attempt: Int,
  )
}

pub type Digests {
  Digests(
    transaction_id: String,
    candidate: String,
    payload: String,
    source: String,
    previous_candidate: String,
    previous_payload: String,
    physical_manifest: String,
    native_artifact: String,
    runtime_evidence: String,
    formal_evidence: String,
  )
}

pub type Window {
  Window(
    created_utc_ms: Int,
    expires_utc_ms: Int,
    created_mono_ms: Int,
    expires_mono_ms: Int,
  )
}

pub type Proposal {
  Proposal(
    digests: Digests,
    execution: Execution,
    host: String,
    boot: String,
    clock_domain: String,
    runtime_resource: String,
    runtime_epoch: Int,
    nonce: String,
    window: Window,
  )
}

pub opaque type Intent {
  Intent(proposal: Proposal, canonical: String, digest: String)
}

fn ascii(s: String, cap: Int) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= cap
  && list.all(string.to_utf_codepoints(s), fn(cp) {
    let c = string.utf_codepoint_to_int(cp)
    { c >= 97 && c <= 122 }
    || { c >= 65 && c <= 90 }
    || { c >= 48 && c <= 57 }
    || c == 45
    || c == 95
    || c == 46
    || c == 58
    || c == 47
  })
}

fn component(s: String) -> Bool {
  s != "" && s != "." && s != ".." && ascii(s, 256)
}

fn workspace(s: String) -> Bool {
  string.byte_size(s) <= 4096
  && string.starts_with(s, "/")
  && list.all(string.split(string.drop_start(s, 1), "/"), component)
}

fn host_name(s: String) -> Bool {
  case string.split(s, ".") {
    [label, "tail55d152", "ts", "net"] ->
      ascii(label, 63)
      && list.all(string.to_graphemes(label), fn(c) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c)
      })
      && !string.starts_with(label, "-")
      && !string.ends_with(label, "-")
    _ -> False
  }
}

pub fn valid_digest(s: String) -> Bool {
  string.byte_size(s) == 71
  && string.starts_with(s, "sha256:")
  && list.all(string.to_graphemes(string.drop_start(s, 7)), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn utc(n: Int) -> Bool {
  n >= 0 && n <= 9_000_000_000_000_000
}

fn mono_ms(n: Int) -> Bool {
  n >= -9_000_000_000_000_000 && n <= 9_000_000_000_000_000
}

fn window(w: Window) -> Bool {
  utc(w.created_utc_ms)
  && utc(w.expires_utc_ms)
  && mono_ms(w.created_mono_ms)
  && mono_ms(w.expires_mono_ms)
  && w.expires_utc_ms > w.created_utc_ms
  && w.expires_mono_ms > w.created_mono_ms
  && w.expires_utc_ms - w.created_utc_ms <= maximum_window_ms
  && w.expires_mono_ms - w.created_mono_ms <= maximum_window_ms
}

fn ordered(fields: List(#(String, json.Json))) -> json.Json {
  json.object(list.sort(fields, fn(a, b) { string.compare(a.0, b.0) }))
}

fn encode(p: Proposal) -> String {
  let d = p.digests
  let e = p.execution
  let w = p.window
  ordered([
    #("domain", json.string(domain)),
    #("version", json.int(1)),
    #(
      "digests",
      ordered([
        #("transaction_id", json.string(d.transaction_id)),
        #("candidate", json.string(d.candidate)),
        #("payload", json.string(d.payload)),
        #("source", json.string(d.source)),
        #("previous_candidate", json.string(d.previous_candidate)),
        #("previous_payload", json.string(d.previous_payload)),
        #("physical_manifest", json.string(d.physical_manifest)),
        #("native_artifact", json.string(d.native_artifact)),
        #("runtime_evidence", json.string(d.runtime_evidence)),
        #("formal_evidence", json.string(d.formal_evidence)),
      ]),
    ),
    #(
      "execution",
      ordered([
        #("workspace", json.string(e.workspace)),
        #("plan", json.string(e.plan)),
        #("task", json.string(e.task)),
        #("worker", json.string(e.worker)),
        #("attempt", json.int(e.attempt)),
      ]),
    ),
    #("host", json.string(p.host)),
    #("boot", json.string(p.boot)),
    #("clock_domain", json.string(p.clock_domain)),
    #("runtime_resource", json.string(p.runtime_resource)),
    #("runtime_epoch", json.int(p.runtime_epoch)),
    #("nonce", json.string(p.nonce)),
    #(
      "window",
      ordered([
        #("created_utc_ms", json.int(w.created_utc_ms)),
        #("expires_utc_ms", json.int(w.expires_utc_ms)),
        #("created_mono_ms", json.int(w.created_mono_ms)),
        #("expires_mono_ms", json.int(w.expires_mono_ms)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn new(p: Proposal) -> Result(Intent, String) {
  let d = p.digests
  let e = p.execution
  case
    list.all(
      [
        d.transaction_id,
        d.candidate,
        d.payload,
        d.source,
        d.previous_candidate,
        d.previous_payload,
        d.physical_manifest,
        d.native_artifact,
        d.runtime_evidence,
        d.formal_evidence,
      ],
      valid_digest,
    )
    && workspace(e.workspace)
    && list.all(
      [e.plan, e.task, e.worker, p.boot, p.clock_domain, p.nonce],
      fn(s) { ascii(s, 256) },
    )
    && e.attempt > 0
    && e.attempt <= 2_147_483_647
    && p.runtime_epoch > 0
    && p.runtime_epoch <= 9_000_000_000_000
    && host_name(p.host)
    && string.starts_with(p.runtime_resource, "runtime:")
    && ascii(p.runtime_resource, 136)
    && string.byte_size(p.runtime_resource) > 8
    && !string.contains(p.runtime_resource, "/")
    && window(p.window)
  {
    False -> Error("invalid_release_proposal")
    True -> {
      let canonical = encode(p)
      case string.byte_size(canonical) <= 16_384 {
        True -> Ok(Intent(p, canonical, files.digest(canonical)))
        False -> Error("release_intent_bound")
      }
    }
  }
}

pub fn canonical_json(i: Intent) -> String {
  i.canonical
}

pub fn digest(i: Intent) -> String {
  i.digest
}

pub fn transaction_id(i: Intent) -> String {
  i.proposal.digests.transaction_id
}

pub fn effect_id(i: Intent) -> String {
  transaction_id(i)
}

pub fn candidate(i: Intent) -> String {
  i.proposal.digests.candidate
}

pub fn manifest(i: Intent) -> String {
  i.proposal.digests.physical_manifest
}

pub fn bindings(i: Intent) -> Digests {
  i.proposal.digests
}

pub fn execution(i: Intent) -> Execution {
  i.proposal.execution
}

pub fn host(i: Intent) -> String {
  i.proposal.host
}

pub fn boot(i: Intent) -> String {
  i.proposal.boot
}

pub fn clock_domain(i: Intent) -> String {
  i.proposal.clock_domain
}

pub fn runtime_resource(i: Intent) -> String {
  i.proposal.runtime_resource
}

pub fn runtime_epoch(i: Intent) -> Int {
  i.proposal.runtime_epoch
}

pub fn nonce(i: Intent) -> String {
  i.proposal.nonce
}

pub fn created_utc_ms(i: Intent) -> Int {
  i.proposal.window.created_utc_ms
}

pub fn created_mono_ms(i: Intent) -> Int {
  i.proposal.window.created_mono_ms
}

pub fn expires_utc_ms(i: Intent) -> Int {
  i.proposal.window.expires_utc_ms
}

pub fn expires_mono_ms(i: Intent) -> Int {
  i.proposal.window.expires_mono_ms
}

pub fn purpose(_i: Intent) -> String {
  approval_purpose
}

pub fn valid_at(
  i: Intent,
  host: String,
  boot: String,
  clock_domain: String,
  now_utc_ms: Int,
  now_mono_ms: Int,
) -> Bool {
  i.proposal.host == host
  && i.proposal.boot == boot
  && i.proposal.clock_domain == clock_domain
  && utc(now_utc_ms)
  && mono_ms(now_mono_ms)
  && now_utc_ms >= created_utc_ms(i)
  && now_utc_ms < expires_utc_ms(i)
  && now_mono_ms >= created_mono_ms(i)
  && now_mono_ms < expires_mono_ms(i)
}

pub fn valid_receipt_window(
  i: Intent,
  now_utc_ms: Int,
  issued: Int,
  not_before: Int,
  expires: Int,
) -> Bool {
  created_utc_ms(i) <= issued
  && issued <= not_before
  && not_before <= now_utc_ms
  && now_utc_ms < expires
  && expires <= expires_utc_ms(i)
}
