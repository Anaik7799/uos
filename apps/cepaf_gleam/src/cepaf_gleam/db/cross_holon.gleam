// STAMP: SC-HOLON-003, SC-ZENOH-001
// AOR: AOR-HOLON-003, AOR-GLM-005
// Criticality: Level 2 (HIGH) - Cross-Holon State Synchronization
//
// Provides inter-holon communication, conflict resolution, and
// distributed state management via Zenoh pub/sub.

import gleam/int
import gleam/json

// =============================================================================
// Types
// =============================================================================

pub type ConflictResolution {
  LastWriterWins
  FirstWriterWins
  MergeAll
}

pub type CasResult {
  CasSuccess
  CasFailed(current_version: Int)
  CasRetry
}

pub type CrossHolonRequest {
  CrossHolonRequest(
    source_holon: String,
    target_holon: String,
    operation: String,
    payload: String,
  )
}

pub type CrossHolonResponse {
  CrossHolonOk(data: String)
  CrossHolonError(reason: String)
  CrossHolonTimeout
}

// =============================================================================
// FFI Stubs
// =============================================================================

pub fn send_request(
  req: CrossHolonRequest,
) -> Result(CrossHolonResponse, String) {
  let _ = req
  panic as "NYI: requires Zenoh FFI (SC-HOLON-003)"
}

pub fn compare_and_swap(
  handle: String,
  key: String,
  expected: Int,
  value: String,
) -> Result(CasResult, String) {
  let _ = handle
  let _ = key
  let _ = expected
  let _ = value
  panic as "NYI: requires FFI (SC-HOLON-003)"
}

pub fn resolve_conflict(
  a: String,
  b: String,
  strategy: ConflictResolution,
) -> String {
  let _ = a
  let _ = b
  let _ = strategy
  panic as "NYI: requires merge logic (SC-HOLON-003)"
}

pub fn broadcast_state(
  holon_id: String,
  state_json: String,
) -> Result(Nil, String) {
  let _ = holon_id
  let _ = state_json
  panic as "NYI: requires Zenoh (SC-HOLON-003)"
}

pub fn subscribe_updates(holon_id: String) -> Result(Nil, String) {
  let _ = holon_id
  panic as "NYI: requires Zenoh (SC-HOLON-003)"
}

pub fn get_remote_state(holon_id: String) -> Result(String, String) {
  let _ = holon_id
  panic as "NYI: requires Zenoh (SC-HOLON-003)"
}

// =============================================================================
// Pure Helper Functions
// =============================================================================

pub fn conflict_resolution_to_string(r: ConflictResolution) -> String {
  case r {
    LastWriterWins -> "last_writer_wins"
    FirstWriterWins -> "first_writer_wins"
    MergeAll -> "merge_all"
  }
}

pub fn cas_result_to_string(r: CasResult) -> String {
  case r {
    CasSuccess -> "success"
    CasFailed(version) -> "failed:version=" <> int.to_string(version)
    CasRetry -> "retry"
  }
}

pub fn request_to_json(r: CrossHolonRequest) -> json.Json {
  json.object([
    #("source_holon", json.string(r.source_holon)),
    #("target_holon", json.string(r.target_holon)),
    #("operation", json.string(r.operation)),
    #("payload", json.string(r.payload)),
  ])
}

pub fn response_to_json(r: CrossHolonResponse) -> json.Json {
  case r {
    CrossHolonOk(data) ->
      json.object([
        #("status", json.string("ok")),
        #("data", json.string(data)),
      ])
    CrossHolonError(reason) ->
      json.object([
        #("status", json.string("error")),
        #("reason", json.string(reason)),
      ])
    CrossHolonTimeout -> json.object([#("status", json.string("timeout"))])
  }
}
