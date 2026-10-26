//// Telegram /rotate-keys controlled-action adapter (wave 3, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backend: vault_kek_rotation (pure KEK rotation policy). Key rotation is a
//// real secret effect: live rotation needs an opened vault handle and
//// production authority, neither of which is boundable in development, so
//// `execute` returns `backend_unavailable:vault_kek_rotation` and writes
//// nothing. `preview` only evaluates the pure policy against DECLARED numbers
//// (rotation window and key age supplied by the caller); it never reads key
//// material, vault state or the clock. This module grants no authority.
////
//// Decision state is one of: parse (pure), preview (pure), execute (refusal).

import cepaf_gleam/harness/files
import cepaf_gleam/vault_kek_rotation as policy
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_rotation_days = 3650

const max_age_days = 36_500

const backend = "vault_kek_rotation"

const seconds_per_day = 86_400

pub opaque type Request {
  Request(rotation_days: Int, age_days: Int)
}

pub fn literal() -> String {
  "/rotate-keys"
}

fn usage() -> String {
  "usage: /rotate-keys <declared_rotation_days 1..3650> <declared_key_age_days 0..36500>"
}

fn number(text: String, low: Int, high: Int) -> Result(Int, Nil) {
  let size = string.byte_size(text)
  case
    size >= 1
    && size <= 5
    && list.all(string.to_graphemes(text), fn(c) {
      string.contains("0123456789", c)
    })
  {
    False -> Error(Nil)
    True ->
      case int.parse(text) {
        Ok(n) if n >= low && n <= high -> Ok(n)
        _ -> Error(Nil)
      }
  }
}

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error("args_bound: " <> usage())
    True ->
      case
        string.split(string.trim(args), " ")
        |> list.filter(fn(part) { part != "" })
      {
        [days, age] ->
          case
            number(days, 1, max_rotation_days),
            number(age, 0, max_age_days)
          {
            Ok(d), Ok(a) -> Ok(Request(d, a))
            _, _ -> Error(usage())
          }
        _ -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  "rotate-keys-"
  <> files.digest(
    "telegram_action_rotate_keys/v1\n"
    <> int.to_string(r.rotation_days)
    <> "\n"
    <> int.to_string(r.age_days),
  )
}

fn decision(r: Request) -> policy.RotationDecision {
  policy.decide_rotation(policy.RotationContext(
    current_ts: r.age_days * seconds_per_day,
    last_rotation_ts: 0,
    rotation_days: r.rotation_days,
    vault_state: policy.ActiveState,
  ))
}

fn decision_label(d: policy.RotationDecision) -> String {
  case d {
    policy.NotDue -> "not_due"
    policy.DueSoon(_) -> "due_soon"
    policy.Overdue(_) -> "overdue"
    policy.Expired(_) -> "expired"
    policy.CannotRotate(_) -> "cannot_rotate"
  }
}

fn reply(fields: List(#(String, json.Json))) -> String {
  let text = json.object(fields) |> json.to_string
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False -> "{\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

/// Read-only. Evaluates the pure rotation policy against the caller's
/// DECLARED window and age. No vault, key material or clock is read.
pub fn preview(r: Request) -> String {
  let d = decision(r)
  reply([
    #("status", json.string("preview")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("confidence", json.string("declared")),
    #(
      "state_source",
      json.string("declared rotation window and key age; vault not read"),
    ),
    #("rotation_days", json.int(r.rotation_days)),
    #("key_age_days", json.int(r.age_days)),
    #("policy_decision", json.string(decision_label(d))),
    #("severity_tier", json.string(policy.severity_tier(d))),
    #("urgency_color", json.string(policy.urgency_color(d))),
    #("should_propose_reseal", json.bool(policy.should_propose_reseal(d))),
    #("blocking", json.bool(policy.is_blocking(d))),
    #(
      "plan",
      json.array(
        [
          "operator runs re-seal-tpm (SC-VAULT-023, operator-gated)",
          "new KEK sealed through the TPM, passphrase, KMS chain",
          "every unseal logged to the immutable register (SC-VAULT-015)",
        ],
        json.string,
      ),
    ),
    #("key_material_read", json.bool(False)),
    #("execute", json.string("unavailable:" <> backend)),
    #(
      "unavailable_reason",
      json.string(
        "live rotation requires an opened vault and production authority",
      ),
    ),
    #("approval_required", json.bool(True)),
    #("authority", json.string("NONE")),
  ])
}

/// Typed `backend_unavailable` reply for the service to relay.
pub fn unavailable_reply(r: Request) -> String {
  reply([
    #("status", json.string("backend_unavailable")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("backend", json.string(backend)),
    #(
      "reason",
      json.string(
        "live rotation requires an opened vault and production authority",
      ),
    ),
    #("authority", json.string("NONE")),
  ])
}

/// Never rotates anything and never creates a file. A missing evidence_dir is
/// still an Error, so the service cannot mistake the refusal for a receipt.
pub fn execute(_r: Request, evidence_dir: String) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> Error("backend_unavailable:" <> backend)
    _ -> Error("evidence_dir_missing")
  }
}
