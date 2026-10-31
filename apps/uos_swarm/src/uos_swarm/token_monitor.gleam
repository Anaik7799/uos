//// Read-only invocation accounting over the existing coord.Usage carrier.
//// No scheduler, currency pricing, task authority, persistent ledger or dispatch.
//// Denotation: unique (provider, request_id) -> immutable final receipt.
//// Laws: replay idempotence; conflicting replay refusal; order-independent sum;
//// missing usage remains unknown; reasoning is a subset of output, never added.
//// Unknown cost independently holds advice after unknown usage, before limits.

import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/coord

pub type Receipt {
  Receipt(
    provider: String,
    request_id: String,
    usage: Option(coord.Usage),
    reasoning_tokens: Option(Int),
    estimated_nanodollars: Option(Int),
    failed: Bool,
  )
}

pub opaque type Monitor {
  Monitor(receipts: Dict(#(String, String), Receipt))
}

pub type Policy {
  Policy(max_tokens: Int, max_calls: Int)
}

pub type Decision {
  HoldUnknownUsage
  HoldUnknownCost
  StopNewCalls
  ContinueWithinObservedLimit
}

pub type Summary {
  Summary(
    unique_calls: Int,
    known_calls: Int,
    unknown_calls: Int,
    failed_calls: Int,
    input_tokens: Int,
    output_tokens: Int,
    cache_read_tokens: Int,
    cache_write_tokens: Int,
    estimated_nanodollars: Int,
    unknown_cost_calls: Int,
  )
}

const counter_limit = 1_000_000_000

pub const max_receipts = 4096

pub fn new() -> Monitor {
  Monitor(dict.new())
}

fn valid_id(s: String) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= 160
  && list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/-",
      c,
    )
  })
}

fn count(n: Int) -> Bool {
  n >= 0 && n <= counter_limit
}

pub fn tokens(u: coord.Usage) -> Int {
  u.input_tokens + u.output_tokens + u.cache_read + u.cache_write
}

fn valid(r: Receipt) -> Bool {
  valid_id(r.provider)
  && valid_id(r.request_id)
  && case r.estimated_nanodollars {
    None -> True
    Some(n) -> n >= 0 && n <= 1_000_000_000_000
  }
  && case r.usage, r.reasoning_tokens {
    None, None -> True
    None, Some(_) -> False
    Some(u), reasoning ->
      valid_id(u.agent)
      && valid_id(u.model)
      && list.all(
        [
          u.input_tokens,
          u.output_tokens,
          u.cache_read,
          u.cache_write,
          u.tool_uses,
          u.wall_ms,
        ],
        count,
      )
      && tokens(u) <= counter_limit
      && case reasoning {
        None -> True
        Some(n) -> count(n) && n <= u.output_tokens
      }
  }
}

/// Complete final invocation receipts only; cumulative snapshots are not deltas.
/// A new revision of an existing receipt conflicts and must be reconciled upstream.
pub fn record(m: Monitor, r: Receipt) -> Result(Monitor, String) {
  case valid(r) {
    False -> Error("invalid_receipt")
    True -> {
      let key = #(r.provider, r.request_id)
      case dict.get(m.receipts, key) {
        Ok(previous) ->
          case previous == r {
            True -> Ok(m)
            False -> Error("conflicting_receipt")
          }
        Error(_) ->
          case dict.size(m.receipts) < max_receipts {
            True -> Ok(Monitor(dict.insert(m.receipts, key, r)))
            False -> Error("receipt_limit")
          }
      }
    }
  }
}

pub fn collect(rows: List(Receipt)) -> Result(Monitor, String) {
  case list.length(rows) <= max_receipts {
    False -> Error("receipt_limit")
    True -> list.try_fold(rows, new(), record)
  }
}

fn add(s: Summary, r: Receipt) -> Summary {
  let s =
    Summary(
      ..s,
      unique_calls: s.unique_calls + 1,
      failed_calls: s.failed_calls
        + case r.failed {
          True -> 1
          False -> 0
        },
    )
  let s = case r.estimated_nanodollars {
    None -> Summary(..s, unknown_cost_calls: s.unknown_cost_calls + 1)
    Some(n) -> Summary(..s, estimated_nanodollars: s.estimated_nanodollars + n)
  }
  case r.usage {
    None -> Summary(..s, unknown_calls: s.unknown_calls + 1)
    Some(u) ->
      Summary(
        ..s,
        known_calls: s.known_calls + 1,
        input_tokens: s.input_tokens + u.input_tokens,
        output_tokens: s.output_tokens + u.output_tokens,
        cache_read_tokens: s.cache_read_tokens + u.cache_read,
        cache_write_tokens: s.cache_write_tokens + u.cache_write,
      )
  }
}

pub fn summary(m: Monitor) -> Summary {
  dict.values(m.receipts)
  |> list.fold(Summary(0, 0, 0, 0, 0, 0, 0, 0, 0, 0), add)
}

pub fn total(s: Summary) -> Int {
  s.input_tokens + s.output_tokens + s.cache_read_tokens + s.cache_write_tokens
}

/// Observation recommendation only. No authority to start a call follows.
pub fn decide(m: Monitor, p: Policy) -> Result(Decision, String) {
  case
    p.max_tokens > 0
    && p.max_tokens <= 4_096_000_000_000
    && p.max_calls > 0
    && p.max_calls <= max_receipts
  {
    False -> Error("invalid_policy")
    True -> {
      let s = summary(m)
      case
        s.unknown_calls > 0,
        s.unknown_cost_calls > 0,
        total(s) >= p.max_tokens || s.unique_calls >= p.max_calls
      {
        True, _, _ -> Ok(HoldUnknownUsage)
        False, True, _ -> Ok(HoldUnknownCost)
        False, False, True -> Ok(StopNewCalls)
        False, False, False -> Ok(ContinueWithinObservedLimit)
      }
    }
  }
}

/// Reuse the coordinator carrier without mutating or re-aggregating its ledger.
pub fn usages(m: Monitor) -> List(coord.Usage) {
  list.filter_map(dict.values(m.receipts), fn(r) {
    case r.usage {
      None -> Error(Nil)
      Some(u) -> Ok(u)
    }
  })
}

pub fn report(m: Monitor, p: Policy) -> Result(json.Json, String) {
  use d <- result.try(decide(m, p))
  let s = summary(m)
  let decision = case d {
    HoldUnknownUsage -> "HOLD_UNKNOWN_USAGE"
    HoldUnknownCost -> "HOLD_UNKNOWN_COST"
    StopNewCalls -> "STOP_NEW_CALLS"
    ContinueWithinObservedLimit -> "WITHIN_OBSERVED_LIMIT_ONLY"
  }
  let hints = [
    "Recall top 1-2 fresh canonical documents; keep stable instruction prefixes",
    "Prefer accepted-work yield and full failed-attempt cost over cheap token price",
    "Reasoning tokens are included in output; cache counters are distinct input classes",
    "New calls still require canonical Sa-plan and daily budget admission",
  ]
  Ok(
    json.object([
      #("status", json.string("REPORT_ONLY")),
      #("authority", json.string("NONE")),
      #("hard_cap_enforced", json.bool(False)),
      #("decision", json.string(decision)),
      #("unique_calls", json.int(s.unique_calls)),
      #("known_usage_calls", json.int(s.known_calls)),
      #("unknown_usage_calls", json.int(s.unknown_calls)),
      #("invocations_reporting_error", json.int(s.failed_calls)),
      #(
        "accepted_work_outcomes",
        json.string("UNVERIFIED_SEPARATE_REVIEW_REQUIRED"),
      ),
      #("input_tokens_uncached", json.int(s.input_tokens)),
      #("output_tokens_including_reasoning", json.int(s.output_tokens)),
      #("cache_read_input_tokens", json.int(s.cache_read_tokens)),
      #("cache_write_input_tokens", json.int(s.cache_write_tokens)),
      #("known_total_tokens", json.int(total(s))),
      #("estimated_nanodollars", json.int(s.estimated_nanodollars)),
      #("unknown_cost_calls", json.int(s.unknown_cost_calls)),
      #(
        "billing_basis",
        json.string(
          "unverified_receipt_sdk_or_list_price_estimates_not_invoice",
        ),
      ),
      #(
        "known_input_tokens",
        json.int(s.input_tokens + s.cache_read_tokens + s.cache_write_tokens),
      ),
      #(
        "cache_read_basis_points_of_input",
        case s.input_tokens + s.cache_read_tokens + s.cache_write_tokens {
          0 -> json.null()
          n -> json.int(s.cache_read_tokens * 10_000 / n)
        },
      ),
      #("max_tokens", json.int(p.max_tokens)),
      #("max_calls", json.int(p.max_calls)),
      #("optimization_hints", json.array(hints, json.string)),
      #("calls", json.array(dict.values(m.receipts), receipt_json)),
    ]),
  )
}

fn receipt_json(r: Receipt) -> json.Json {
  let counters = case r.usage {
    None -> json.null()
    Some(u) ->
      json.object([
        #("agent", json.string(u.agent)),
        #("model", json.string(u.model)),
        #("input_tokens_uncached", json.int(u.input_tokens)),
        #("output_tokens_including_reasoning", json.int(u.output_tokens)),
        #("cache_read_input_tokens", json.int(u.cache_read)),
        #("cache_write_input_tokens", json.int(u.cache_write)),
        #("total_tokens", json.int(tokens(u))),
      ])
  }
  json.object([
    #("provider", json.string(r.provider)),
    #("request_id", json.string(r.request_id)),
    #("failure_observed", json.bool(r.failed)),
    #("usage", counters),
    #("reasoning_tokens_subset", case r.reasoning_tokens {
      None -> json.null()
      Some(n) -> json.int(n)
    }),
    #("estimated_nanodollars", case r.estimated_nanodollars {
      None -> json.null()
      Some(n) -> json.int(n)
    }),
  ])
}
