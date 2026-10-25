//// =============================================================================
//// [C3I-SIL6-EVIDENCE] Pure Gleam Typed Telemetry Evidence Projection
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/c3i/evidence</module>
////     <lineage>UOS Truthful Telemetry & Freshness Projection</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-RISK-PRIORITY-001, SC-CHECKLIST-001, SC-EVO-KPI-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="truthful-projection">
////       Maps raw payloads and native runtime state to verified epistemic status.
////       Never fabricates timestamps; treats missing/stub/stale data as non-fresh.
////       Does not overclaim all_wiring_functional without websocket evidence.
////       Validates payload domain shapes, declared units, and negative controls.
////     </morphism>
////   </transformations>
//// </c3i-module>

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const default_max_age_ms = 60_000

pub type Staleness {
  Fresh
  Stale
  Unavailable
  Unknown
}

pub fn staleness_to_string(staleness: Staleness) -> String {
  case staleness {
    Fresh -> "fresh"
    Stale -> "stale"
    Unavailable -> "unavailable"
    Unknown -> "unknown"
  }
}

pub type ProvenanceQuality {
  LiveVerified(observed_at_ms: Int, age_ms: Int)
  StubPayload(reason: String)
  EmptyPayload
  MalformedPayload
  MissingTimestamp
  ConflictingTimestamps
  MissingRequiredFields(fields: String)
  WrongTypedField(detail: String)
  OfflineOrError(reason: String)
  FutureDated(skew_ms: Int)
  StaleSample(age_ms: Int)
}

pub type EvidenceProjection {
  EvidenceProjection(
    runtime_loaded: Bool,
    plan_status_valid: Bool,
    system_health_valid: Bool,
    plan_status_length: Int,
    health_length: Int,
    samples_fresh: Bool,
    ws_planning_active: Bool,
    ws_dashboard_active: Bool,
    ws_availability: String,
    all_wiring_functional: Bool,
    staleness: Staleness,
    detail: String,
  )
}

pub type JsonContext {
  InObject(keys: List(String), expect_key: Bool)
  InArray
}

fn scan_json_tokens(
  chars: List(String),
  stack: List(JsonContext),
  in_string: Bool,
  escaped: Bool,
  current_str: String,
) -> Result(Nil, String) {
  case chars {
    [] -> Ok(Nil)
    [char, ..rest] -> {
      case in_string {
        True -> {
          case escaped {
            True ->
              scan_json_tokens(
                rest,
                stack,
                True,
                False,
                current_str <> "\\" <> char,
              )
            False -> {
              case char {
                "\\" -> scan_json_tokens(rest, stack, True, True, current_str)
                "\"" -> {
                  case stack {
                    [InObject(keys, True), ..tail] -> {
                      use key <- result.try(
                        json.parse("\"" <> current_str <> "\"", decode.string)
                        |> result.map_error(fn(_) { "Invalid JSON object key" }),
                      )
                      case list.contains(keys, key) {
                        True -> Error("Duplicate JSON key: " <> key)
                        False ->
                          scan_json_tokens(
                            rest,
                            [InObject([key, ..keys], False), ..tail],
                            False,
                            False,
                            "",
                          )
                      }
                    }
                    _ -> scan_json_tokens(rest, stack, False, False, "")
                  }
                }
                _ ->
                  scan_json_tokens(
                    rest,
                    stack,
                    True,
                    False,
                    current_str <> char,
                  )
              }
            }
          }
        }
        False -> {
          case char {
            "\"" -> scan_json_tokens(rest, stack, True, False, "")
            "{" ->
              scan_json_tokens(
                rest,
                [InObject([], True), ..stack],
                False,
                False,
                "",
              )
            "}" -> {
              case stack {
                [InObject(_, _), ..tail] ->
                  scan_json_tokens(rest, tail, False, False, "")
                _ -> scan_json_tokens(rest, stack, False, False, "")
              }
            }
            "[" -> scan_json_tokens(rest, [InArray, ..stack], False, False, "")
            "]" -> {
              case stack {
                [InArray, ..tail] ->
                  scan_json_tokens(rest, tail, False, False, "")
                _ -> scan_json_tokens(rest, stack, False, False, "")
              }
            }
            "," -> {
              case stack {
                [InObject(keys, _), ..tail] ->
                  scan_json_tokens(
                    rest,
                    [InObject(keys, True), ..tail],
                    False,
                    False,
                    "",
                  )
                _ -> scan_json_tokens(rest, stack, False, False, "")
              }
            }
            _ -> scan_json_tokens(rest, stack, False, False, "")
          }
        }
      }
    }
  }
}

/// Verify that a JSON object contains no ambiguous duplicate keys at any depth.
pub fn check_no_duplicate_keys(input: String) -> Result(Nil, String) {
  case string.byte_size(input) > 262_144 {
    True -> Error("Telemetry payload exceeds 256 KiB")
    False -> {
      use _ <- result.try(
        json.parse(input, decode.dynamic)
        |> result.map_error(fn(_) { "Malformed JSON" }),
      )
      scan_json_tokens(string.to_graphemes(input), [], False, False, "")
    }
  }
}

/// Detect if a payload is a known fallback stub, empty, or uninitialized structurally.
/// No substring-matching authority: decodes typed fields directly.
pub fn is_stub(payload: String) -> Bool {
  let trimmed = string.trim(payload)
  case trimmed {
    "" | "{}" | "[]" -> True
    _ -> {
      // Check structural error indicating uninitialized / unloaded NIF
      let error_decoder = {
        use opt_err <- decode.optional_field(
          "error",
          None,
          decode.map(decode.string, Some),
        )
        decode.success(opt_err)
      }
      let is_unloaded = case json.parse(trimmed, error_decoder) {
        Ok(Some(err)) -> {
          let lower = string.lowercase(err)
          string.contains(lower, "not loaded") || string.contains(lower, "stub")
        }
        _ -> False
      }

      // Check structural health fallback stub (c3i_nif.erl line 57):
      // container_count: 0, healthy_count: 0, threat_level: "unknown", zenoh_connected: false
      let health_decoder = {
        use containers <- decode.optional_field(
          "container_count",
          -1,
          decode.int,
        )
        use healthy <- decode.optional_field("healthy_count", -1, decode.int)
        use threat <- decode.optional_field("threat_level", "", decode.string)
        use zenoh <- decode.optional_field("zenoh_connected", True, decode.bool)
        decode.success(#(containers, healthy, threat, zenoh))
      }
      let is_health_fallback = case json.parse(trimmed, health_decoder) {
        Ok(#(0, 0, "unknown", False)) -> True
        _ -> False
      }

      // Check structural plan fallback stub (c3i_nif.erl line 49):
      // active: 0, pending: 0, completed: 0, blocked: 0, total: 0
      let plan_decoder = {
        use active <- decode.optional_field("active", -1, decode.int)
        use pending <- decode.optional_field("pending", -1, decode.int)
        use completed <- decode.optional_field("completed", -1, decode.int)
        use blocked <- decode.optional_field("blocked", 0, decode.int)
        use total <- decode.optional_field("total", 0, decode.int)
        decode.success(#(active, pending, completed, blocked, total))
      }
      let is_plan_fallback = case json.parse(trimmed, plan_decoder) {
        Ok(#(0, 0, 0, 0, 0)) -> True
        _ -> False
      }

      // Zero work is valid observed data when the producer supplied an
      // unambiguous timestamp. The native fallback has no timestamp.
      let lacks_timestamp = case extract_declared_timestamp_ms(trimmed) {
        Ok(_) -> False
        Error(_) -> True
      }
      is_unloaded
      || { lacks_timestamp && { is_health_fallback || is_plan_fallback } }
    }
  }
}

/// Structural check for offline or error status variants.
/// Parses typed status/error fields; no fragile text substring authority.
fn check_offline_or_error(payload: String) -> Result(Nil, ProvenanceQuality) {
  // Check typed status field if present
  let status_decoder = {
    use opt_dyn <- decode.optional_field(
      "status",
      None,
      decode.map(decode.dynamic, Some),
    )
    decode.success(opt_dyn)
  }

  let status_res = case json.parse(payload, status_decoder) {
    Error(_) -> Ok(Nil)
    Ok(None) -> Ok(Nil)
    Ok(Some(dyn)) -> {
      case decode.run(dyn, decode.string) {
        Error(_) -> Error(WrongTypedField("status field must be a string"))
        Ok(s) -> {
          let lower = string.lowercase(string.trim(s))
          case lower {
            "offline"
            | "down"
            | "error"
            | "failed"
            | "unhealthy"
            | "degraded"
            | "unloaded" ->
              Error(OfflineOrError(
                "Status field indicates offline/error: " <> s,
              ))
            _ -> Ok(Nil)
          }
        }
      }
    }
  }

  use Nil <- result.try(status_res)

  // Check typed error field if present
  let error_decoder = {
    use opt_dyn <- decode.optional_field(
      "error",
      None,
      decode.map(decode.dynamic, Some),
    )
    decode.success(opt_dyn)
  }

  case json.parse(payload, error_decoder) {
    Error(_) -> Ok(Nil)
    Ok(None) -> Ok(Nil)
    Ok(Some(dyn)) -> {
      case decode.run(dyn, decode.string) {
        Ok(err_str) -> {
          let lower = string.lowercase(string.trim(err_str))
          case
            string.contains(lower, "not loaded")
            || string.contains(lower, "stub")
          {
            True -> Error(StubPayload("error: " <> err_str))
            False -> Error(OfflineOrError("error: " <> err_str))
          }
        }
        Error(_) ->
          case decode.run(dyn, decode.bool) {
            Ok(True) -> Error(OfflineOrError("error flag is true"))
            _ -> Error(OfflineOrError("error indicator present"))
          }
      }
    }
  }
}

fn extract_alias(
  payload: String,
  field_name: String,
) -> Result(Option(Int), ProvenanceQuality) {
  let decoder = {
    use opt_dyn <- decode.optional_field(
      field_name,
      None,
      decode.map(decode.dynamic, Some),
    )
    decode.success(opt_dyn)
  }

  case json.parse(payload, decoder) {
    Error(_) -> Error(MalformedPayload)
    Ok(None) -> Ok(None)
    Ok(Some(dyn)) -> {
      case decode.run(dyn, decode.int) {
        Ok(val) ->
          case val < 0 {
            True -> Error(WrongTypedField(field_name <> " cannot be negative"))
            False -> Ok(Some(val))
          }
        Error(_) ->
          Error(WrongTypedField(field_name <> " has invalid non-integer type"))
      }
    }
  }
}

/// Extract observation timestamp in milliseconds from explicit declared millisecond fields.
/// Refuses conflicting timestamps; rejects ambiguous duplicate keys; rejects type errors
/// on any declared alias even if a sibling alias is valid.
pub fn extract_declared_timestamp_ms(
  payload: String,
) -> Result(Int, ProvenanceQuality) {
  case check_no_duplicate_keys(payload) {
    Error(_) -> Error(ConflictingTimestamps)
    Ok(Nil) -> {
      use opt1 <- result.try(extract_alias(payload, "timestamp_ms"))
      use opt2 <- result.try(extract_alias(payload, "ts_ms"))
      use opt3 <- result.try(extract_alias(payload, "observed_at_ms"))

      let present_ts =
        [opt1, opt2, opt3]
        |> list.filter_map(fn(opt) {
          case opt {
            Some(v) -> Ok(v)
            None -> Error(Nil)
          }
        })

      case present_ts {
        [] -> Error(MissingTimestamp)
        [first, ..rest] -> {
          case list.all(rest, fn(x) { x == first }) {
            True -> Ok(first)
            False -> Error(ConflictingTimestamps)
          }
        }
      }
    }
  }
}

/// Validate plan status sample shape, required integer counters, and timestamp.
/// Rejects negative counters, ambiguous duplicate keys, and offline/error states structurally.
pub fn validate_plan_sample(
  payload: String,
  now_ms: Int,
  max_age_ms: Int,
) -> ProvenanceQuality {
  let trimmed = string.trim(payload)
  case string.length(trimmed) < 2 {
    True -> EmptyPayload
    False -> {
      case check_no_duplicate_keys(trimmed) {
        Error(_) -> MalformedPayload
        Ok(Nil) -> {
          case is_stub(trimmed) {
            True -> StubPayload("Known fallback stub or unloaded marker")
            False -> {
              case check_offline_or_error(trimmed) {
                Error(err) -> err
                Ok(Nil) -> {
                  let plan_decoder = {
                    use active <- decode.field("active", decode.int)
                    use pending <- decode.field("pending", decode.int)
                    use completed <- decode.field("completed", decode.int)
                    use blocked <- decode.optional_field(
                      "blocked",
                      0,
                      decode.int,
                    )
                    use total <- decode.optional_field("total", 0, decode.int)
                    decode.success(#(active, pending, completed, blocked, total))
                  }
                  case json.parse(trimmed, plan_decoder) {
                    Error(json.UnableToDecode(_)) ->
                      case
                        json.parse(
                          trimmed,
                          decode.map(decode.dynamic, fn(_) { Nil }),
                        )
                      {
                        Ok(_) ->
                          MissingRequiredFields("active, pending, completed")
                        Error(_) -> MalformedPayload
                      }
                    Error(_) -> MalformedPayload
                    Ok(#(active, pending, completed, blocked, total)) -> {
                      case
                        active < 0
                        || pending < 0
                        || completed < 0
                        || blocked < 0
                        || total < 0
                      {
                        True ->
                          WrongTypedField(
                            "Plan counters cannot be negative: active="
                            <> int.to_string(active)
                            <> ", pending="
                            <> int.to_string(pending)
                            <> ", completed="
                            <> int.to_string(completed),
                          )
                        False -> {
                          case extract_declared_timestamp_ms(trimmed) {
                            Error(err) -> err
                            Ok(ts) -> {
                              case ts > now_ms {
                                True -> FutureDated(ts - now_ms)
                                False -> {
                                  let age = now_ms - ts
                                  case age > max_age_ms {
                                    True -> StaleSample(age)
                                    False -> LiveVerified(ts, age)
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Validate system health sample shape, required health fields, and timestamp.
/// Rejects negative counts, healthy_count > container_count, ambiguous duplicate keys,
/// and offline/error states structurally.
pub fn validate_health_sample(
  payload: String,
  now_ms: Int,
  max_age_ms: Int,
) -> ProvenanceQuality {
  let trimmed = string.trim(payload)
  case string.length(trimmed) < 2 {
    True -> EmptyPayload
    False -> {
      case check_no_duplicate_keys(trimmed) {
        Error(_) -> MalformedPayload
        Ok(Nil) -> {
          case is_stub(trimmed) {
            True -> StubPayload("Known fallback stub or unloaded marker")
            False -> {
              case check_offline_or_error(trimmed) {
                Error(err) -> err
                Ok(Nil) -> {
                  let health_decoder = {
                    use containers <- decode.field(
                      "container_count",
                      decode.int,
                    )
                    use healthy <- decode.field("healthy_count", decode.int)
                    use threat <- decode.field("threat_level", decode.string)
                    use zenoh <- decode.field("zenoh_connected", decode.bool)
                    decode.success(#(containers, healthy, threat, zenoh))
                  }
                  case json.parse(trimmed, health_decoder) {
                    Error(json.UnableToDecode(_)) ->
                      case
                        json.parse(
                          trimmed,
                          decode.map(decode.dynamic, fn(_) { Nil }),
                        )
                      {
                        Ok(_) ->
                          MissingRequiredFields(
                            "container_count, healthy_count, threat_level, zenoh_connected",
                          )
                        Error(_) -> MalformedPayload
                      }
                    Error(_) -> MalformedPayload
                    Ok(#(containers, healthy, threat, _zenoh)) -> {
                      case containers < 0 || healthy < 0 {
                        True ->
                          WrongTypedField(
                            "Health container counts cannot be negative: container_count="
                            <> int.to_string(containers)
                            <> ", healthy_count="
                            <> int.to_string(healthy),
                          )
                        False -> {
                          case healthy > containers {
                            True ->
                              WrongTypedField(
                                "healthy_count ("
                                <> int.to_string(healthy)
                                <> ") exceeds container_count ("
                                <> int.to_string(containers)
                                <> ")",
                              )
                            False -> {
                              case threat == "unknown" {
                                True ->
                                  StubPayload(
                                    "Health threat_level is unknown (unobserved)",
                                  )
                                False -> {
                                  case extract_declared_timestamp_ms(trimmed) {
                                    Error(err) -> err
                                    Ok(ts) -> {
                                      case ts > now_ms {
                                        True -> FutureDated(ts - now_ms)
                                        False -> {
                                          let age = now_ms - ts
                                          case age > max_age_ms {
                                            True -> StaleSample(age)
                                            False -> LiveVerified(ts, age)
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Deterministic, pure evaluation of freshness with explicit inputs.
/// all_wiring_functional must NOT be True without websocket evidence.
pub fn evaluate_freshness_custom(
  runtime_loaded: Bool,
  plan_payload: String,
  health_payload: String,
  now_ms: Int,
) -> EvidenceProjection {
  let plan_len = string.length(plan_payload)
  let health_len = string.length(health_payload)

  case runtime_loaded {
    False ->
      EvidenceProjection(
        runtime_loaded: False,
        plan_status_valid: False,
        system_health_valid: False,
        plan_status_length: plan_len,
        health_length: health_len,
        samples_fresh: False,
        ws_planning_active: False,
        ws_dashboard_active: False,
        ws_availability: "unknown",
        all_wiring_functional: False,
        staleness: Unavailable,
        detail: "Native NIF runtime not loaded; telemetry unavailable",
      )
    True -> {
      let plan_quality =
        validate_plan_sample(plan_payload, now_ms, default_max_age_ms)
      let health_quality =
        validate_health_sample(health_payload, now_ms, default_max_age_ms)

      let plan_ok = case plan_quality {
        LiveVerified(_, _) -> True
        _ -> False
      }
      let health_ok = case health_quality {
        LiveVerified(_, _) -> True
        _ -> False
      }

      // all_wiring_functional MUST NOT be True without websocket evidence!
      // Since websocket availability is UNKNOWN without connection evidence,
      // all_wiring_functional stays False to prevent overclaiming whole wiring.
      let all_wiring_functional = False

      case plan_quality, health_quality {
        LiveVerified(_, _), LiveVerified(_, _) ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: True,
            system_health_valid: True,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: True,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: all_wiring_functional,
            staleness: Fresh,
            detail: "Live telemetry samples verified within 60s freshness window; websocket evidence unobserved",
          )
        StaleSample(_), _ | _, StaleSample(_) ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: plan_ok,
            system_health_valid: health_ok,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Stale,
            detail: "Telemetry sample exceeds 60s freshness threshold",
          )
        FutureDated(_), _ | _, FutureDated(_) ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: plan_ok,
            system_health_valid: health_ok,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unknown,
            detail: "Telemetry sample carries future timestamp; cannot imply actual observed data",
          )
        ConflictingTimestamps, _ | _, ConflictingTimestamps ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: False,
            system_health_valid: False,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unknown,
            detail: "Telemetry sample carries conflicting timestamp fields",
          )
        MissingTimestamp, _ | _, MissingTimestamp ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: plan_ok,
            system_health_valid: health_ok,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unknown,
            detail: "Telemetry sample lacks observation timestamp provenance",
          )
        MissingRequiredFields(fields), _ | _, MissingRequiredFields(fields) ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: False,
            system_health_valid: False,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unavailable,
            detail: "Telemetry sample missing required domain fields: "
              <> fields,
          )
        OfflineOrError(reason), _ | _, OfflineOrError(reason) ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: False,
            system_health_valid: False,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unavailable,
            detail: "Telemetry payload indicates error or offline state: "
              <> reason,
          )
        StubPayload(reason), _ | _, StubPayload(reason) ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: False,
            system_health_valid: False,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unavailable,
            detail: "NIF returned fallback stub payload: " <> reason,
          )
        _, _ ->
          EvidenceProjection(
            runtime_loaded: True,
            plan_status_valid: False,
            system_health_valid: False,
            plan_status_length: plan_len,
            health_length: health_len,
            samples_fresh: False,
            ws_planning_active: False,
            ws_dashboard_active: False,
            ws_availability: "unknown",
            all_wiring_functional: False,
            staleness: Unavailable,
            detail: "Telemetry sample is empty, malformed, or invalid shape",
          )
      }
    }
  }
}

/// Live freshness evaluation reading current NIF status and runtime state
pub fn evaluate_freshness(now_ms: Int) -> EvidenceProjection {
  evaluate_freshness_custom(
    c3i_nif.runtime_loaded(),
    c3i_nif.plan_status(),
    c3i_nif.system_health(),
    now_ms,
  )
}

/// Convert evidence projection to standard API JSON response
pub fn to_freshness_json(proj: EvidenceProjection) -> String {
  json.object([
    #("page", json.string("Data Freshness")),
    #("runtime_loaded", json.bool(proj.runtime_loaded)),
    #("nif_plan_status", json.bool(proj.plan_status_valid)),
    #("nif_system_health", json.bool(proj.system_health_valid)),
    #("plan_status_length", json.int(proj.plan_status_length)),
    #("health_length", json.int(proj.health_length)),
    #("samples_fresh", json.bool(proj.samples_fresh)),
    #("ws_planning_active", json.bool(proj.ws_planning_active)),
    #("ws_dashboard_active", json.bool(proj.ws_dashboard_active)),
    #("ws_planning_availability", json.string(proj.ws_availability)),
    #("ws_dashboard_availability", json.string(proj.ws_availability)),
    #("ws_evidence", json.string("absent")),
    #("all_wiring_functional", json.bool(proj.all_wiring_functional)),
    #("staleness", json.string(staleness_to_string(proj.staleness))),
    #("detail", json.string(proj.detail)),
  ])
  |> json.to_string()
}
