//// Display projections of bounded recorded evidence. No execution or admission.

import cepaf_gleam/harness/telegram_verification_report as report
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string

fn require(ok: Bool) -> Result(Nil, String) {
  case ok {
    True -> Ok(Nil)
    False -> Error("mini_evidence_refused")
  }
}

fn boolean(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

fn checked(
  raw: String,
  now: Int,
  expected_schema: String,
) -> Result(Int, String) {
  use _ <- result.try(require(string.byte_size(raw) <= 32_768 && now > 0))
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use authority <- decode.field("authority", decode.string)
    use admission <- decode.field("runtime_admission", decode.string)
    use observed <- decode.field("observed_at_ms", decode.int)
    decode.success(#(schema, authority, admission, observed))
  }
  use #(schema, authority, admission, observed) <- result.try(
    json.parse(raw, decoder) |> result.replace_error("mini_evidence_json"),
  )
  let at = observed / 1000
  use _ <- result.try(require(
    schema == expected_schema
    && authority == "observation_only"
    && admission == "NOT_GRANTED"
    && observed > 0
    && at <= now
    && now - at <= 30,
  ))
  Ok(at)
}

fn emit(
  at: Int,
  source: String,
  fields: List(#(String, String)),
) -> Result(api.Observation, String) {
  let keys = list.map(fields, fn(p) { p.0 })
  use _ <- result.try(require(
    list.length(fields) <= 100
    && list.length(list.unique(keys)) == list.length(keys)
    && list.all(fields, fn(p) {
      string.byte_size(p.0) <= 128 && string.byte_size(p.1) <= 2048
    }),
  ))
  Ok(api.Observed(at, source, dict.from_list(fields)))
}

fn hex(value: String, size: Int) -> Bool {
  string.byte_size(value) == size
  && list.all(string.to_graphemes(value), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

type FMode {
  FMode(
    id: String,
    cause: String,
    effect: String,
    controls: String,
    s: Int,
    o: Int,
    det: Int,
    rpn: Int,
  )
}

type FRow {
  FRow(
    id: String,
    task: String,
    state: String,
    observed: String,
    until: String,
    freshness: String,
    max_rpn: Int,
    modes: List(FMode),
  )
}

fn mode_decoder() -> decode.Decoder(FMode) {
  use id <- decode.field("id", decode.string)
  use cause <- decode.field("cause", decode.string)
  use effect <- decode.field("effect", decode.string)
  use controls <- decode.field("controls", decode.string)
  use s <- decode.field("s", decode.int)
  use o <- decode.field("o", decode.int)
  use det <- decode.field("det", decode.int)
  use rpn <- decode.field("rpn", decode.int)
  decode.success(FMode(id, cause, effect, controls, s, o, det, rpn))
}

fn fmea_row() -> decode.Decoder(FRow) {
  use id <- decode.field("assessment_id", decode.string)
  use task <- decode.field("task_id", decode.string)
  use state <- decode.field("recorded_task_state", decode.string)
  use observed <- decode.field("observed_at", decode.string)
  use until <- decode.field("valid_until", decode.string)
  use freshness <- decode.field("freshness", decode.string)
  use rpn <- decode.field("max_rpn", decode.int)
  use modes <- decode.field("fmea_modes", decode.list(mode_decoder()))
  decode.success(FRow(id, task, state, observed, until, freshness, rpn, modes))
}

fn valid_row(row: FRow) -> Bool {
  row.id != ""
  && string.byte_size(row.id) <= 128
  && row.task != ""
  && string.byte_size(row.task) <= 240
  && list.contains(["fresh", "stale", "future"], row.freshness)
  && row.modes != []
  && list.length(row.modes) <= 32
  && list.length(list.unique(list.map(row.modes, fn(m) { m.id })))
  == list.length(row.modes)
  && list.all(row.modes, fn(m) {
    m.id != ""
    && string.byte_size(m.id) <= 128
    && m.s >= 1
    && m.s <= 5
    && m.o >= 1
    && m.o <= 5
    && m.det >= 1
    && m.det <= 5
    && m.rpn == m.s * m.o * m.det
    && list.all([m.cause, m.effect, m.controls], fn(t) {
      string.byte_size(t) <= 1024
    })
  })
  && row.max_rpn == list.fold(row.modes, 0, fn(n, m) { int.max(n, m.rpn) })
}

fn row_fields(row: FRow, index: Int) -> List(#(String, String)) {
  let prefix = "Assessment " <> int.to_string(index + 1)
  let sorted =
    list.sort(row.modes, fn(a, b) {
      case int.compare(b.rpn, a.rpn) {
        order.Eq -> string.compare(a.id, b.id)
        other -> other
      }
    })
  let shown = list.take(sorted, 3)
  [
    #(prefix, row.task <> " | " <> row.id <> " | recorded state: " <> row.state),
    #(
      prefix <> " freshness",
      row.freshness
        <> " | observed: "
        <> row.observed
        <> " | valid until: "
        <> row.until,
    ),
    #(
      prefix <> " modes",
      "Max RPN "
        <> int.to_string(row.max_rpn)
        <> "; shown "
        <> int.to_string(list.length(shown))
        <> " of "
        <> int.to_string(list.length(sorted))
        <> " modes, ordered by RPN; omitted=" <> int.to_string(list.length(sorted) - list.length(shown)),
    ),
    ..list.index_map(shown, fn(m, i) {
      let key = prefix <> " mode " <> int.to_string(i + 1)
      [
        #(
          key,
          m.id
            <> " | S/O/Det "
            <> int.to_string(m.s)
            <> "/"
            <> int.to_string(m.o)
            <> "/"
            <> int.to_string(m.det)
            <> " | RPN "
            <> int.to_string(m.rpn),
        ),
        #(key <> " cause", m.cause),
        #(key <> " effect", m.effect),
        #(key <> " controls", m.controls),
      ]
    })
    |> list.flatten
  ]
}

pub fn fmea(
  raw: String,
  expected_plan: String,
  now_seconds: Int,
) -> Result(api.Observation, String) {
  use at <- result.try(checked(raw, now_seconds, "uos.telegram.fmea.v1"))
  let decoder = {
    use plan <- decode.field("plan_id", decode.string)
    use scope <- decode.field("scope", decode.string)
    use digest <- decode.field("source_sha256", decode.string)
    use total <- decode.field("total_matching_tasks", decode.int)
    use selected <- decode.field("selected_tasks", decode.int)
    use shown <- decode.field("shown", decode.int)
    use truncated <- decode.field("truncated", decode.bool)
    use rows <- decode.field("assessments", decode.list(fmea_row()))
    decode.success(#(
      plan,
      scope,
      digest,
      total,
      selected,
      shown,
      truncated,
      rows,
    ))
  }
  use #(plan, scope, digest, total, selected, shown, truncated, rows) <- result.try(
    json.parse(raw, decoder) |> result.replace_error("mini_fmea_json"),
  )
  use _ <- result.try(require(
    plan == expected_plan
    && scope == "recorded_engineering_risk_assessments"
    && hex(digest, 64)
    && total > 0
    && total <= 1000
    && selected > 0
    && selected <= total
    && shown == list.length(rows)
    && shown == int.min(selected, 5)
    && truncated == { selected > shown }
    && list.all(rows, valid_row)
    && list.length(list.unique(list.map(rows, fn(r) { r.task }))) == shown,
  ))
  emit(at, "recorded_fmea", [
    #("Plan", plan),
    #("Source SHA256", digest),
    #(
      "Assessments",
      "Showing "
        <> int.to_string(shown)
        <> " of "
        <> int.to_string(selected)
        <> " selected; "
        <> int.to_string(total)
        <> " matching tasks; truncated="
        <> boolean(truncated),
    ),
    #("Runtime admission", "NOT_GRANTED"),
    #(
      "Limitation",
      "Recorded engineering estimates, not measured runtime failure rates. Underlying evidence is not verified by this read.",
    ),
    ..list.index_map(rows, row_fields)
    |> list.flatten
  ])
}

type VRow {
  VRow(id: String, name: String, state: String, reason: String, credit: Bool)
}

fn verification_row() -> decode.Decoder(VRow) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use state <- decode.field("state", decode.string)
  use reason <- decode.field("reason", decode.string)
  use credit <- decode.field("admission_credit", decode.bool)
  decode.success(VRow(id, name, state, reason, credit))
}

pub fn verification(
  raw: String,
  expected_candidate: String,
  now_seconds: Int,
) -> Result(api.Observation, String) {
  use at <- result.try(checked(raw, now_seconds, "uos.telegram.verification.v1"))
  let decoder = {
    use candidate <- decode.field("candidate", decode.string)
    use source <- decode.field("source_sha256", decode.string)
    use scope <- decode.field("scope", decode.string)
    use view <- decode.field("view", decode.string)
    use selector <- decode.field("selector", decode.string)
    use observed <- decode.field("record_observed_at_ms", decode.int)
    use expires <- decode.field("record_expires_at_ms", decode.int)
    use stale <- decode.field("stale", decode.bool)
    use passes <- decode.field("current_recorded_pass_count", decode.int)
    use missing <- decode.field("missing_count", decode.int)
    use verified <- decode.field("evidence_bytes_verified", decode.bool)
    use executed <- decode.field("gates_executed", decode.bool)
    use rows <- decode.field("rows", decode.list(verification_row()))
    decode.success(#(
      candidate,
      source,
      scope,
      view,
      selector,
      observed,
      expires,
      stale,
      passes,
      missing,
      verified,
      executed,
      rows,
    ))
  }
  use
    #(
      candidate,
      source,
      scope,
      view,
      selector,
      observed,
      expires,
      stale,
      passes,
      missing,
      verified,
      executed,
      rows,
    )
  <- result.try(
    json.parse(raw, decoder) |> result.replace_error("mini_verification_json"),
  )
  let ids = list.map(rows, fn(r) { r.id })
  use _ <- result.try(require(
    candidate == expected_candidate
    && hex(candidate, 40)
    && hex(source, 64)
    && scope == "configured_candidate_record_only"
    && view == "checklist"
    && selector == ""
    && !verified
    && !executed
    && observed > 0
    && expires > observed
    && passes >= 0
    && passes <= 18
    && missing >= 0
    && missing <= 18
    && list.length(rows) == 18
    && list.length(list.unique(ids)) == 18
    && list.all(rows, fn(r) {
      !r.credit
      && list.any(report.checkpoints, fn(p) { p.0 == r.id })
      && list.contains(
        [
          "RECORDED_PASS",
          "RECORDED_FAIL",
          "RECORDED_PARTIAL",
          "RECORDED_NOT_APPLICABLE",
          "UNKNOWN",
          "UNRUN",
          "STALE",
        ],
        r.state,
      )
    })
    && case stale {
      True ->
        passes == 0
        && list.all(rows, fn(r) { r.state == "STALE" || r.state == "UNKNOWN" })
      False -> passes == list.count(rows, fn(r) { r.state == "RECORDED_PASS" })
    },
  ))
  emit(at, "candidate_verification_record", [
    #("Candidate", candidate),
    #("Source SHA256", source),
    #("Record observed (ms)", int.to_string(observed)),
    #("Record expires (ms)", int.to_string(expires)),
    #("Record stale", boolean(stale)),
    #("Recorded passes", int.to_string(passes)),
    #("Missing checkpoints", int.to_string(missing)),
    #("Evidence bytes verified", "false"),
    #("Gates executed", "false"),
    #("Runtime admission", "NOT_GRANTED"),
    #(
      "Limitation",
      "Recorded evidence only; referenced evidence bytes and producer authority are not verified. Not runtime admission.",
    ),
    ..list.map(rows, fn(r) {
      #(r.id <> " " <> r.name, r.state <> ": " <> r.reason)
    })
  ])
}
