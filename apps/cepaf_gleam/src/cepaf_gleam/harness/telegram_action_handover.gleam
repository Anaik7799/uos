//// ControlledAction adapter for `/handover` (contract 20261026-0115).
//// Effect: create ONE handover journal skeleton (13 SC-JOURNAL-v3 headings) as
//// a Markdown file inside the caller-supplied evidence directory, plus an
//// exclusive-create receipt. parse and preview never mutate. execute is called
//// only by the service after approval and fences; this module grants nothing.
//// The skeleton is NOT a completed journal and is never written under docs/.

import cepaf_gleam/harness/files
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(slug: String)
}

const literal_text = "/handover"

const max_args = 256

const max_slug = 40

const max_reply = 3500

const slug_alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-"

const usage = "usage: /handover <slug> (lowercase kebab, [a-z0-9-], at most 40 bytes)"

/// SC-JOURNAL-v3 canonical order (contracts/rules/20260912-0745-...).
const sections = [
  "Scope & Trigger", "Pre-State Assessment", "Execution Detail",
  "Root Cause Analysis", "Fix Taxonomy", "Patterns & Anti-Patterns Discovered",
  "Verification Matrix", "Files Modified", "Architectural Observations",
  "Remaining Gaps", "Metrics Summary", "STAMP & Constitutional Alignment",
  "Conclusion",
]

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_nanos() -> Int

@external(erlang, "cepaf_gleam_ffi", "nanos_to_iso8601")
fn iso8601(nanos: Int) -> String

pub fn literal() -> String {
  literal_text
}

pub fn section_titles() -> List(String) {
  sections
}

/// Pure: no clock, no filesystem.
pub fn parse(args: String) -> Result(Request, String) {
  let slug =
    args
    |> string.trim
    |> string.lowercase
    |> string.replace(" ", "-")
  case
    string.byte_size(args) <= max_args
    && string.byte_size(slug) >= 1
    && string.byte_size(slug) <= max_slug
    && list.all(string.to_graphemes(slug), fn(c) {
      string.contains(slug_alphabet, c)
    })
    && !string.starts_with(slug, "-")
    && !string.ends_with(slug, "-")
    && !string.contains(slug, "--")
  {
    True -> Ok(Request(slug))
    False -> Error(usage)
  }
}

pub fn slug(r: Request) -> String {
  r.slug
}

pub fn effect_id(r: Request) -> String {
  files.digest("uos.telegram.action.handover.v1|slug=" <> r.slug)
}

/// `YYYYMMDD-HHSS` from an ISO-8601 UTC string (HH = hour, SS = seconds, per
/// contracts/rules/timestamp-mandate.md).
pub fn prefix_from_iso(iso: String) -> Result(String, String) {
  let graphemes = string.to_graphemes(iso)
  let digit = fn(i: Int) {
    case list.drop(graphemes, i) |> list.first {
      Ok(c) -> string.contains("0123456789", c)
      Error(_) -> False
    }
  }
  let at = fn(from: Int, len: Int) {
    graphemes |> list.drop(from) |> list.take(len) |> string.join("")
  }
  case
    list.length(graphemes) >= 19
    && list.all([0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18], digit)
    && at(4, 1) == "-"
    && at(7, 1) == "-"
    && at(10, 1) == "T"
    && at(13, 1) == ":"
    && at(16, 1) == ":"
  {
    True ->
      Ok(at(0, 4) <> at(5, 2) <> at(8, 2) <> "-" <> at(11, 2) <> at(17, 2))
    False -> Error("clock_format_invalid")
  }
}

fn file_name(r: Request, nanos: Int) -> Result(String, String) {
  use prefix <- result.try(prefix_from_iso(iso8601(nanos)))
  Ok(prefix <> "-handover-" <> r.slug <> ".md")
}

fn skeleton(r: Request, iso: String) -> String {
  let numbered =
    sections
    |> list.index_map(fn(title, i) {
      "## " <> int.to_string(i + 1) <> ". " <> title <> "\n\n_TODO: author._\n"
    })
    |> string.join("\n")
  "# Handover journal skeleton: "
  <> r.slug
  <> "\n\n#fractal-l0 #fractal-l5 #zk-adr #zero-muda\n\n"
  <> "Skeleton created "
  <> iso
  <> " by the Telegram `/handover` adapter, effect `"
  <> effect_id(r)
  <> "`. This is NOT a completed journal and grants no authority or admission.\n"
  <> "EV ceiling 93; EV-94..109 NOT_ADMITTED.\n\n"
  <> numbered
}

fn reply(fields: List(#(String, json.Json))) -> String {
  let text = json.object(fields) |> json.to_string
  case string.byte_size(text) <= max_reply {
    True -> text
    False ->
      json.object([
        #("status", json.string("denied")),
        #("literal", json.string(literal_text)),
        #("reason", json.string("reply_bound")),
      ])
      |> json.to_string
  }
}

/// Read-only. Observes the host clock to say which file name would be created
/// now; the name at execution time can differ by the elapsed seconds.
pub fn preview(r: Request) -> String {
  let name = case file_name(r, now_nanos()) {
    Ok(n) -> n
    Error(_) -> "clock_unavailable"
  }
  reply([
    #("status", json.string("preview")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("confidence", json.string("observed")),
    #("effect", json.string("create handover journal skeleton in evidence_dir")),
    #("slug", json.string(r.slug)),
    #("file_if_executed_now", json.string(name)),
    #("sections", json.int(list.length(sections))),
    #("writes", json.array(["<effect_id>.json", name], json.string)),
    #("docs_directory_untouched", json.bool(True)),
    #("authority", json.string("NONE")),
  ])
}

fn receipt_fields(
  status: String,
  effect: String,
  artifact: String,
  artifact_sha: String,
  bytes: Int,
) -> String {
  reply([
    #("status", json.string(status)),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect)),
    #("artifact", json.string(artifact)),
    #("artifact_sha256", json.string(artifact_sha)),
    #("artifact_bytes", json.int(bytes)),
    #("authority", json.string("NONE")),
  ])
}

type Stored {
  Stored(effect: String, artifact: String, sha: String, bytes: Int)
}

fn stored_decoder() -> decode.Decoder(Stored) {
  use effect <- decode.field("effect_id", decode.string)
  use artifact <- decode.field("artifact", decode.string)
  use sha <- decode.field("artifact_sha256", decode.string)
  use bytes <- decode.field("artifact_bytes", decode.int)
  decode.success(Stored(effect, artifact, sha, bytes))
}

fn duplicate(r: Request, dir: String) -> Result(String, String) {
  use raw <- result.try(files.read(dir, effect_id(r) <> ".json"))
  use stored <- result.try(
    json.parse(raw, stored_decoder())
    |> result.replace_error("receipt_unreadable"),
  )
  case stored.effect == effect_id(r) {
    True ->
      Ok(receipt_fields(
        "duplicate",
        stored.effect,
        stored.artifact,
        stored.sha,
        stored.bytes,
      ))
    False -> Error("receipt_identity_mismatch")
  }
}

/// Idempotent by effect_id. The evidence directory must already exist.
pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  execute_at(r, evidence_dir, now_nanos())
}

/// `execute` with an injected host-clock reading (nanoseconds since epoch).
pub fn execute_at(
  r: Request,
  evidence_dir: String,
  nanos: Int,
) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> run(r, evidence_dir, nanos)
    _ -> Error("evidence_dir_unavailable")
  }
}

fn run(r: Request, dir: String, nanos: Int) -> Result(String, String) {
  case duplicate(r, dir) {
    Ok(text) -> Ok(text)
    Error(_) -> {
      case simplifile.is_file(dir <> "/" <> effect_id(r) <> ".json") {
        Ok(True) -> Error("receipt_unreadable")
        _ -> create(r, dir, nanos)
      }
    }
  }
}

fn create(r: Request, dir: String, nanos: Int) -> Result(String, String) {
  use name <- result.try(file_name(r, nanos))
  let content = skeleton(r, iso8601(nanos))
  use _ <- result.try(files.create(dir, name, content))
  let body =
    receipt_fields(
      "executed",
      effect_id(r),
      name,
      files.digest(content),
      string.byte_size(content),
    )
  case files.create(dir, effect_id(r) <> ".json", body) {
    Ok(_) -> Ok(body)
    // A concurrent execution may have won the receipt: report it, not a second.
    Error(_) -> duplicate(r, dir)
  }
}
