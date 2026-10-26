import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_export_audit as export
import cepaf_gleam/vault_audit_query.{AuditEntry}
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3-export-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = export.parse(args)
  r
}

fn entries() {
  [
    AuditEntry(100, "put", "SECRET_NAME_ALPHA", 1, "nif"),
    AuditEntry(200, "get", "SECRET_NAME_ALPHA", 1, "operator-cli"),
    AuditEntry(300, "get", "SECRET_NAME_ORPHAN", 1, "nif"),
    AuditEntry(400, "destroy", "SECRET_NAME_ALPHA", 1, "nif"),
  ]
}

pub fn literal_and_parse_positive_test() {
  export.literal() |> should.equal("/export-audit")
  let default_id = export.effect_id(req(""))
  string.length(default_id) |> should.equal(64)
  default_id |> should.equal(export.effect_id(req("limit=50")))
  { default_id == export.effect_id(req("limit=51")) } |> should.equal(False)
  { default_id == export.effect_id(req("event=get")) } |> should.equal(False)
  export.effect_id(req("event=get limit=7"))
  |> should.equal(export.effect_id(req("limit=7 event=get")))
  let _ = req("event=put")
  let _ = req("limit=200")
  let _ = req("limit=1")
  Nil
}

pub fn parse_negative_test() {
  list.each(
    [
      "limit=0",
      "limit=201",
      "limit=abc",
      "limit=",
      "limit=-1",
      "event=secret",
      "event=",
      "event=get event=put",
      "limit=1 limit=2",
      "limit=1 event=get extra",
      "bogus",
      "name=x",
      string.repeat("a", 257),
    ],
    fn(input) {
      case export.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage:") |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn preview_shape_and_confidence_label_test() {
  let text = export.preview(req("event=get limit=5"))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "\"literal\":\"/export-audit\"") |> should.equal(True)
  string.contains(text, "\"event_filter\":\"get\"") |> should.equal(True)
  string.contains(text, "\"limit\":5") |> should.equal(True)
  string.contains(text, "unavailable:rusty_vault_nif") |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn execute_reports_backend_unavailable_without_writing_test() {
  let dir = fresh("unavail")
  export.execute(req(""), dir)
  |> should.equal(Error("backend_unavailable:rusty_vault_nif"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
  let reply = export.unavailable_reply(req(""))
  string.contains(reply, "\"status\":\"backend_unavailable\"")
  |> should.equal(True)
  string.contains(reply, "\"backend\":\"rusty_vault_nif\"")
  |> should.equal(True)
}

pub fn execute_refuses_missing_evidence_dir_test() {
  let dir = base <> "does-not-exist"
  let _ = simplifile.delete(dir)
  export.execute(req(""), dir)
  |> should.equal(Error("evidence_dir_unavailable"))
  export.execute_with(req(""), dir, entries())
  |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}

pub fn execute_with_writes_receipt_and_export_then_duplicates_test() {
  let dir = fresh("exec")
  let r = req("")
  let assert Ok(first) = export.execute_with(r, dir, entries())
  string.contains(first, "\"status\":\"executed\"") |> should.equal(True)
  let id = export.effect_id(r)
  let assert Ok(receipt) = simplifile.read(dir <> "/" <> id <> ".json")
  receipt |> should.equal(first)
  let assert Ok(artifact) =
    simplifile.read(dir <> "/" <> id <> "-audit-export.json")
  string.contains(
    first,
    "\"artifact_sha256\":\"" <> files.digest(artifact) <> "\"",
  )
  |> should.equal(True)
  // Counts, window and digests are present...
  string.contains(artifact, "\"metadata_only\":true") |> should.equal(True)
  string.contains(artifact, "\"source_entries_total\":4") |> should.equal(True)
  string.contains(artifact, "\"matched_total\":4") |> should.equal(True)
  string.contains(artifact, "\"exported\":4") |> should.equal(True)
  string.contains(artifact, "\"orphan_gets\":1") |> should.equal(True)
  string.contains(artifact, "\"window\":{\"min_ts\":100,\"max_ts\":400}")
  |> should.equal(True)
  string.contains(artifact, "\"get\":2") |> should.equal(True)
  string.contains(artifact, "\"entry_sha256\":\"") |> should.equal(True)
  // ...and no secret names or callers ever leave the vault boundary.
  string.contains(artifact, "SECRET_NAME") |> should.equal(False)
  string.contains(artifact, "operator-cli") |> should.equal(False)
  // Repeat with different source data: stored receipt, no second artifact.
  let assert Ok(second) = export.execute_with(r, dir, [])
  string.contains(second, "\"status\":\"duplicate\"") |> should.equal(True)
  string.contains(
    second,
    "\"artifact_sha256\":\"" <> files.digest(artifact) <> "\"",
  )
  |> should.equal(True)
  let assert Ok(names) = simplifile.read_directory(dir)
  list.length(names) |> should.equal(2)
}

pub fn execute_with_filters_limits_and_handles_empty_source_test() {
  let dir = fresh("filter")
  let assert Ok(_) =
    export.execute_with(req("event=get limit=1"), dir, entries())
  let id = export.effect_id(req("event=get limit=1"))
  let assert Ok(artifact) =
    simplifile.read(dir <> "/" <> id <> "-audit-export.json")
  string.contains(artifact, "\"matched_total\":2") |> should.equal(True)
  string.contains(artifact, "\"exported\":1") |> should.equal(True)
  // Newest first: the single exported entry is ts 300.
  string.contains(artifact, "\"window\":{\"min_ts\":300,\"max_ts\":300}")
  |> should.equal(True)
  let empty = fresh("empty")
  let assert Ok(_) = export.execute_with(req(""), empty, [])
  let assert Ok(body) =
    simplifile.read(
      empty <> "/" <> export.effect_id(req("")) <> "-audit-export.json",
    )
  string.contains(body, "\"window\":null") |> should.equal(True)
  string.contains(body, "\"exported\":0") |> should.equal(True)
}
