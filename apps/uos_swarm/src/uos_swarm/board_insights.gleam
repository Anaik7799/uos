//// Read-only evidence algebra for discovery, board analysis and system status.
//// Report ≙ scoped immutable messages + independently sourced telemetry + gaps.
//// Union is idempotent by event identity; conflicting identities are quarantined.
//// Correlation is evidence of association, never execution, admission or authority.

import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/clock_contract as clock
import uos_tui/telemetry

pub type Scope {
  Scope(hive_id: String, tenant_id: String, bind_legacy_snapshot: Bool)
}

pub type Signal {
  StructuredLog
  Span
  CollectorAccepted
  BackendVisible
}

pub type Severity {
  Info
  Warning
  ErrorSeverity
  UnknownSeverity
}

pub type Sample {
  Sample(
    id: String,
    source_ref: String,
    hive_id: String,
    tenant_id: String,
    trace_id: String,
    span_id: String,
    message_id: Option(String),
    candidate_ref: Option(String),
    service: String,
    observed_us: Int,
    signal: Signal,
    severity: Severity,
  )
}

pub type Query {
  Query(scope: Scope, now_us: Int, ttl_us: Int, window_us: Int, limit: Int)
}

pub type Agent {
  Agent(
    id: String,
    declared_model: String,
    last_message_us: Int,
    last_heartbeat_us: Option(Int),
    heartbeat_fresh: Bool,
    declared_session: Option(String),
    topics: List(String),
  )
}

pub type Correlation {
  Correlation(
    message_id: String,
    sample_id: String,
    source_ref: String,
    match_kind: String,
  )
}

pub type Finding {
  Finding(code: String, subject_ref: String, detail: String)
}

pub type Knowledge {
  Knowledge(message_id: String, kind: String, claim: String, basis: String)
}

pub type Report {
  Report(
    query: Query,
    messages: List(board.Message),
    agents: List(Agent),
    samples: List(Sample),
    correlations: List(Correlation),
    findings: List(Finding),
    knowledge: List(Knowledge),
    total_messages: Int,
    duplicate_count: Int,
    rejected_count: Int,
    clock_status: String,
  )
}

pub fn attribute(message: board.Message, key: String) -> Option(String) {
  message.payload
  |> list.find(fn(p) { p.0 == key })
  |> result.map(fn(p) { p.1 })
  |> option.from_result
}

fn in_scope(message: board.Message, scope: Scope) -> Bool {
  message.swarm == scope.hive_id
  && case attribute(message, "tenant_id") {
    Some(tenant) -> tenant == scope.tenant_id
    None -> scope.bind_legacy_snapshot
  }
}

fn valid_message(message: board.Message) -> Bool {
  board.digest_ok(message)
  && telemetry.is_hex_id(message.trace_id, 32)
  && telemetry.is_hex_id(message.span_id, 16)
  && message.lamport >= 0
  && message.lamport <= clock.max_counter
  && message.ts_us >= 0
}

fn message_order(a: board.Message, b: board.Message) -> order.Order {
  case int.compare(a.ts_us, b.ts_us) {
    order.Eq -> string.compare(a.id, b.id)
    other -> other
  }
}

fn candidate(message: board.Message) -> Option(String) {
  case attribute(message, "candidate_ref") {
    None -> attribute(message, "candidate")
    found -> found
  }
}

/// A finite input snapshot; no parsing side effects or telemetry-derived commands.
pub fn analyse(
  messages: List(board.Message),
  samples: List(Sample),
  query: Query,
  clock_evidence: Option(#(clock.Evidence, clock.Reading)),
) -> Result(Report, String) {
  case
    query.now_us < 0
    || query.ttl_us <= 0
    || query.window_us <= 0
    || query.limit < 1
    || query.limit > 100
    || string.trim(query.scope.hive_id) == ""
    || string.trim(query.scope.tenant_id) == ""
    || list.length(messages) > 10_000
    || list.length(samples) > 10_000
  {
    True -> Error("invalid query or 10000-event snapshot bound exceeded")
    False -> {
      let scoped = list.filter(messages, fn(m) { in_scope(m, query.scope) })
      let groups = list.group(scoped, fn(m) { m.id })
      let #(unique, duplicates, rejected, issues) =
        dict.to_list(groups)
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> list.fold(#([], 0, 0, []), fn(acc, entry) {
          let #(accepted, duplicate_count, bad_count, issues) = acc
          let assert [first, ..rest] = entry.1
          case
            list.all(entry.1, valid_message)
            && list.all(rest, fn(m) {
              m.digest == first.digest && m.signature == first.signature
            })
          {
            False -> #(
              accepted,
              duplicate_count,
              bad_count + list.length(entry.1),
              [
                Finding(
                  "quarantined_identity",
                  entry.0,
                  "Invalid digest or conflicting body/signature; no version selected.",
                ),
                ..issues
              ],
            )
            True -> {
              // Delivery receipts may evolve outside the signed digest. Select a
              // deterministic representative; they are never authentication proof.
              let assert Ok(stable) =
                entry.1
                |> list.sort(fn(a, b) {
                  string.compare(board.to_string(a), board.to_string(b))
                })
                |> list.first
              #(
                [stable, ..accepted],
                duplicate_count + list.length(rest),
                bad_count,
                issues,
              )
            }
          }
        })
      let ordered = list.sort(unique, message_order)
      let future = list.filter(ordered, fn(m) { m.ts_us > query.now_us })
      let recent =
        list.filter(ordered, fn(m) {
          m.ts_us <= query.now_us && query.now_us - m.ts_us <= query.window_us
        })
      let clock_status = case clock_evidence {
        None -> "UNKNOWN: no fresh NTP receipt supplied"
        Some(#(e, now)) ->
          case now.utc_us == query.now_us {
            False -> "INVALID: query time differs from clock observation"
            True ->
              case clock.validate(e, now, clock.strict_policy) {
                Ok(_) -> "PASS: bounded physical clock evidence"
                Error(reason) -> "FAIL: " <> clock.failure_label(reason)
              }
          }
      }
      let clock_ok = string.starts_with(clock_status, "PASS:")
      let agents = discover(recent, query, clock_ok)
      let #(usable_samples, sample_issues) = sample_set(samples, query)
      let correlations = correlate(recent, usable_samples)
      let issues =
        list.flatten([
          list.reverse(issues),
          list.map(future, fn(m) {
            Finding(
              "future_message",
              m.id,
              "Message excluded from current activity; compare host clock evidence.",
            )
          }),
          causal_findings(ordered),
          sample_issues,
          usable_samples
            |> list.filter_map(fn(s) {
              case s.severity {
                ErrorSeverity ->
                  Ok(Finding(
                    "observed_error",
                    s.source_ref <> ":" <> s.id,
                    "Error sample from "
                      <> s.service
                      <> "; inspect linked evidence.",
                  ))
                Warning ->
                  Ok(Finding(
                    "observed_warning",
                    s.source_ref <> ":" <> s.id,
                    "Warning sample from "
                      <> s.service
                      <> "; inspect linked evidence.",
                  ))
                Info -> Error(Nil)
                UnknownSeverity -> Error(Nil)
              }
            }),
          list.filter_map(agents, fn(a) {
            case a.heartbeat_fresh {
              True -> Error(Nil)
              False ->
                Ok(Finding(
                  "heartbeat_not_proven_fresh",
                  a.id,
                  "Message activity is not a process heartbeat or authenticated registration.",
                ))
            }
          }),
        ])
      let issues = case clock_ok {
        True -> issues
        False -> [
          Finding("physical_clock_unverified", "observer", clock_status),
          ..issues
        ]
      }
      let issues = case usable_samples {
        [] -> [
          Finding(
            "telemetry_missing",
            "observation-plane",
            "No scoped current telemetry samples; logging and OTel delivery are UNKNOWN.",
          ),
          ..issues
        ]
        _ -> issues
      }
      Ok(Report(
        query,
        list.reverse(recent) |> list.take(query.limit),
        agents,
        usable_samples,
        correlations,
        issues,
        knowledge(recent),
        list.length(recent),
        duplicates,
        rejected,
        clock_status,
      ))
    }
  }
}

fn discover(
  messages: List(board.Message),
  query: Query,
  clock_ok: Bool,
) -> List(Agent) {
  messages
  |> list.group(fn(m) { m.from.id })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    let ordered = list.sort(entry.1, message_order)
    let assert Ok(last) = ordered |> list.reverse |> list.first
    let heartbeat =
      ordered
      |> list.filter(fn(m) { m.kind == board.Heartbeat })
      |> list.reverse
      |> list.first
      |> result.map(fn(m) { m.ts_us })
      |> option.from_result
    let fresh =
      clock_ok
      && case heartbeat {
        None -> False
        Some(ts) -> ts <= query.now_us && query.now_us - ts <= query.ttl_us
      }
    Agent(
      entry.0,
      last.from.model,
      last.ts_us,
      heartbeat,
      fresh,
      attribute(last, "session"),
      ordered
        |> list.flat_map(fn(m) { m.semantics.ontology_concepts })
        |> list.unique
        |> list.sort(string.compare),
    )
  })
}

pub fn causal_findings(messages: List(board.Message)) -> List(Finding) {
  let index = messages |> list.map(fn(m) { #(m.id, m) }) |> dict.from_list
  messages
  |> list.flat_map(fn(child) {
    let parents =
      list.append(child.causality.caused_by, case child.causality.in_reply_to {
        None -> []
        Some(id) -> [id]
      })
      |> list.unique
    parents
    |> list.filter_map(fn(parent_id) {
      case dict.get(index, parent_id) {
        Error(_) ->
          Ok(Finding(
            "missing_causal_parent",
            child.id,
            "Missing parent " <> parent_id <> "; history is incomplete.",
          ))
        Ok(parent) ->
          case clock.causal_edge(parent.lamport, child.lamport) {
            Ok(_) -> Error(Nil)
            Error(_) ->
              Ok(Finding(
                "lamport_causality_violation",
                child.id,
                "Parent " <> parent_id <> " must have a strictly lower counter.",
              ))
          }
      }
    })
  })
}

fn sample_set(
  samples: List(Sample),
  query: Query,
) -> #(List(Sample), List(Finding)) {
  samples
  |> list.filter(fn(s) {
    s.hive_id == query.scope.hive_id && s.tenant_id == query.scope.tenant_id
  })
  |> list.group(fn(s) { #(s.source_ref, s.id) })
  |> dict.to_list
  |> list.sort(fn(a, b) {
    string.compare(a.0.0 <> "/" <> a.0.1, b.0.0 <> "/" <> b.0.1)
  })
  |> list.fold(#([], []), fn(acc, entry) {
    let assert [s, ..rest] = entry.1
    let valid =
      s.id != ""
      && s.source_ref != ""
      && s.service != ""
      && telemetry.is_hex_id(s.trace_id, 32)
      && telemetry.is_hex_id(s.span_id, 16)
      && s.observed_us >= 0
      && s.observed_us <= query.now_us
      && query.now_us - s.observed_us <= query.window_us
      && list.all(rest, fn(other) { other == s })
    case valid {
      True -> #([s, ..acc.0], acc.1)
      False -> #(acc.0, [
        Finding(
          "telemetry_sample_rejected",
          s.id,
          "Invalid identity, stale/future timestamp, missing provenance or conflicting sample.",
        ),
        ..acc.1
      ])
    }
  })
}

fn correlate(
  messages: List(board.Message),
  samples: List(Sample),
) -> List(Correlation) {
  let traces = list.group(samples, fn(s) { s.trace_id })
  messages
  |> list.flat_map(fn(m) {
    dict.get(traces, m.trace_id)
    |> result.unwrap([])
    |> list.filter_map(fn(s) {
      let candidate_matches = case candidate(m), s.candidate_ref {
        Some(a), Some(b) -> a == b
        _, _ -> True
      }
      let message_matches = case s.message_id {
        None -> True
        Some(id) -> id == m.id
      }
      case candidate_matches && message_matches {
        False -> Error(Nil)
        True ->
          Ok(
            Correlation(m.id, s.id, s.source_ref, case s.message_id {
              Some(_) -> "explicit_message_and_trace"
              None -> "shared_trace_only"
            }),
          )
      }
    })
  })
}

const visible_fields = [
  "task",
  "scope",
  "goal",
  "state",
  "status",
  "gate",
  "gaps",
  "findings",
  "mode",
  "cost",
  "note",
  "summary",
  "reply",
  "correction",
  "remedy",
  "pending",
  "integrated",
  "mandate",
  "action",
  "decision_ref",
  "forecast_ref",
  "candidate",
  "candidate_ref",
  "topic",
  "phase",
]

pub fn summary(message: board.Message) -> String {
  message.payload
  |> list.filter(fn(p) { list.contains(visible_fields, p.0) })
  |> list.map(fn(p) { p.0 <> "=" <> p.1 })
  |> string.join("; ")
  |> string.slice(0, 1200)
}

fn knowledge(messages: List(board.Message)) -> List(Knowledge) {
  messages
  |> list.filter(fn(m) {
    m.kind == board.Report
    || m.kind == board.Verdict
    || m.kind == board.Andon
    || m.kind == board.Answer
  })
  |> list.reverse
  |> list.take(100)
  |> list.map(fn(m) {
    Knowledge(
      m.id,
      board.kind_label(m.kind),
      summary(m),
      "sender_claim; retain source; corroboration and review required",
    )
  })
}

pub fn signal_label(signal: Signal) -> String {
  case signal {
    StructuredLog -> "structured_log"
    Span -> "span"
    CollectorAccepted -> "collector_accepted"
    BackendVisible -> "backend_visible"
  }
}

/// Discovery advertises observed topic participation, not proven capabilities.
pub fn agents_for_topic(report: Report, topic: String) -> List(Agent) {
  list.filter(report.agents, fn(agent) { list.contains(agent.topics, topic) })
}

pub fn to_json(report: Report) -> json.Json {
  json.object([
    #("schema", json.string("uos-board-insights/v1")),
    #("hive_id", json.string(report.query.scope.hive_id)),
    #("tenant_id", json.string(report.query.scope.tenant_id)),
    #(
      "legacy_scope_binding",
      json.bool(report.query.scope.bind_legacy_snapshot),
    ),
    #("as_of_us", json.int(report.query.now_us)),
    #("clock_status", json.string(report.clock_status)),
    #(
      "authority",
      json.string(
        "read-only advisory; digest integrity is not authenticated identity; correlation is not success",
      ),
    ),
    #("total_messages", json.int(report.total_messages)),
    #("duplicate_count", json.int(report.duplicate_count)),
    #("rejected_count", json.int(report.rejected_count)),
    #(
      "chatter",
      json.object([
        #(
          "interpretation",
          json.string(
            "Operational message kinds; emotional sentiment is not measured.",
          ),
        ),
        #("window", json.string("displayed messages")),
        #(
          "kinds",
          json.array(board.kinds, fn(kind) {
            json.object([
              #("kind", json.string(board.kind_label(kind))),
              #(
                "count",
                json.int(
                  report.messages
                  |> list.filter(fn(m) { m.kind == kind })
                  |> list.length,
                ),
              ),
            ])
          }),
        ),
      ]),
    ),
    #(
      "messages",
      json.array(report.messages, fn(m) {
        json.object([
          #("id", json.string(m.id)),
          #("ts_us", json.int(m.ts_us)),
          #("ts_iso", json.string(telemetry.iso8601_us(m.ts_us))),
          #("lamport", json.int(m.lamport)),
          #("from", json.string(m.from.id)),
          #("to", json.string(m.to)),
          #("kind", json.string(board.kind_label(m.kind))),
          #("trace_id", json.string(m.trace_id)),
          #("summary", json.string(summary(m))),
        ])
      }),
    ),
    #(
      "agents",
      json.array(report.agents, fn(a) {
        json.object([
          #("id", json.string(a.id)),
          #("declared_model", json.string(a.declared_model)),
          #("last_message_us", json.int(a.last_message_us)),
          #("last_heartbeat_us", json.nullable(a.last_heartbeat_us, json.int)),
          #("heartbeat_fresh", json.bool(a.heartbeat_fresh)),
          #("declared_session", json.nullable(a.declared_session, json.string)),
          #("topics", json.array(a.topics, json.string)),
        ])
      }),
    ),
    #(
      "telemetry",
      json.array(
        [StructuredLog, Span, CollectorAccepted, BackendVisible],
        fn(signal) {
          let selected =
            list.filter(report.samples, fn(s) { s.signal == signal })
          json.object([
            #("signal", json.string(signal_label(signal))),
            #("sample_count", json.int(list.length(selected))),
            #(
              "status",
              json.string(case selected {
                [] -> "UNKNOWN"
                _ -> "SAMPLES_OBSERVED"
              }),
            ),
            #(
              "source_refs",
              json.array(
                selected |> list.map(fn(s) { s.source_ref }) |> list.unique,
                json.string,
              ),
            ),
          ])
        },
      ),
    ),
    #(
      "correlations",
      json.array(report.correlations, fn(c) {
        json.object([
          #("message_id", json.string(c.message_id)),
          #("sample_id", json.string(c.sample_id)),
          #("source_ref", json.string(c.source_ref)),
          #("match_kind", json.string(c.match_kind)),
        ])
      }),
    ),
    #(
      "findings",
      json.array(report.findings, fn(f) {
        json.object([
          #("code", json.string(f.code)),
          #("subject_ref", json.string(f.subject_ref)),
          #("detail", json.string(f.detail)),
        ])
      }),
    ),
    #(
      "knowledge_candidates",
      json.array(report.knowledge, fn(k) {
        json.object([
          #("message_id", json.string(k.message_id)),
          #("kind", json.string(k.kind)),
          #("claim", json.string(k.claim)),
          #("basis", json.string(k.basis)),
        ])
      }),
    ),
  ])
}

/// Plain terminal output escapes controls; untrusted messages cannot execute ANSI.
fn terminal_safe(value: String) -> String {
  string.inspect(value)
}

pub fn to_text(report: Report) -> String {
  "UOS board / "
  <> terminal_safe(report.query.scope.hive_id)
  <> " / "
  <> terminal_safe(report.query.scope.tenant_id)
  <> "\nAs of "
  <> telemetry.iso8601_us(report.query.now_us)
  <> "\nClock: "
  <> report.clock_status
  <> "\nRead-only observations; runtime health and authentication require independent evidence.\n\n"
  <> {
    report.messages
    |> list.map(fn(m) {
      telemetry.iso8601_us(m.ts_us)
      <> " L="
      <> int.to_string(m.lamport)
      <> " "
      <> terminal_safe(m.from.id)
      <> " "
      <> board.kind_label(m.kind)
      <> " "
      <> terminal_safe(summary(m))
      <> "\n  id="
      <> terminal_safe(m.id)
      <> " trace="
      <> terminal_safe(m.trace_id)
    })
    |> string.join("\n")
  }
  <> "\n\nFindings:\n"
  <> {
    report.findings
    |> list.map(fn(f) {
      f.code
      <> " "
      <> terminal_safe(f.subject_ref)
      <> ": "
      <> terminal_safe(f.detail)
    })
    |> string.join("\n")
  }
}
