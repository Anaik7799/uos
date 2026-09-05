/// Wisp API for KMS Catalog plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Typed JSON via gleam/json — no raw strings (SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/kms/catalog.{type Checkpoint}
import gleam/dict
import gleam/json
import gleam/list

/// Full KMS catalog JSON with checkpoints, total_keys, and active_keys.
pub fn catalog_json(
  checkpoints: List(Checkpoint),
  total_keys: Int,
  active_keys: Int,
) -> String {
  json.object([
    #("plane", json.string("kms")),
    #("total_keys", json.int(total_keys)),
    #("active_keys", json.int(active_keys)),
    #("checkpoint_count", json.int(list.length(checkpoints))),
    #("checkpoints", json.array(checkpoints, encode_checkpoint)),
  ])
  |> json.to_string()
}

/// Single checkpoint detail JSON with key, status, and rotation policy.
pub fn checkpoint_detail_json(
  checkpoint: Checkpoint,
  status: String,
  rotation_policy: String,
) -> String {
  json.object([
    #("plane", json.string("kms")),
    #("key", json.string(checkpoint.id)),
    #("hash", json.string(checkpoint.hash)),
    #("timestamp", json.string(checkpoint.timestamp)),
    #("status", json.string(status)),
    #("rotation_policy", json.string(rotation_policy)),
    #(
      "metadata",
      json.object(
        dict.to_list(checkpoint.metadata)
        |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
      ),
    ),
  ])
  |> json.to_string()
}

fn encode_checkpoint(cp: Checkpoint) -> json.Json {
  json.object([
    #("id", json.string(cp.id)),
    #("hash", json.string(cp.hash)),
    #("timestamp", json.string(cp.timestamp)),
  ])
}
