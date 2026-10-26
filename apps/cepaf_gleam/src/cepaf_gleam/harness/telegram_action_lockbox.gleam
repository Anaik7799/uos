//// Telegram /lockbox controlled-action adapter (wave 3, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backend: vault_kek (KEK chain: TPM, passphrase, KMS) and vault.seal.
//// Sealing the lockbox needs an opened vault handle and production
//// authority, neither of which is boundable in development, and no pure,
//// non-secret bounded effect exists, so `execute` returns
//// `backend_unavailable:vault_kek` and writes nothing. `preview` reports the
//// DECLARED KEK chain parameters only (SC-VAULT-007, SC-VAULT-021); it never
//// reads a secret, a key, a salt, a passphrase or the vault. This module
//// grants no authority.
////
//// Decision state is one of: parse (pure), preview (pure), execute (refusal).

import cepaf_gleam/harness/files
import gleam/json
import gleam/list
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const backend = "vault_kek"

pub opaque type Request {
  Request(reason: String)
}

pub fn literal() -> String {
  "/lockbox"
}

fn usage() -> String {
  "usage: /lockbox seal <reason_token a-z0-9_ max 64>"
}

fn token_ok(text: String) -> Bool {
  let size = string.byte_size(text)
  size >= 1
  && size <= 64
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", c)
  })
}

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error("args_bound: " <> usage())
    True ->
      case
        string.split(string.trim(args), " ")
        |> list.filter(fn(part) { part != "" })
      {
        ["seal", reason] ->
          case token_ok(reason) {
            True -> Ok(Request(reason))
            False -> Error(usage())
          }
        _ -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  "lockbox-" <> files.digest("telegram_action_lockbox/v1\nseal\n" <> r.reason)
}

fn reply(fields: List(#(String, json.Json))) -> String {
  let text = json.object(fields) |> json.to_string
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False -> "{\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

/// Read-only. Declared KEK chain parameters only; no vault, key, salt or
/// passphrase is read.
pub fn preview(r: Request) -> String {
  reply([
    #("status", json.string("preview")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("confidence", json.string("declared")),
    #(
      "state_source",
      json.string(
        "vault_kek declared parameters (SC-VAULT-007, SC-VAULT-021); vault not read",
      ),
    ),
    #("operation", json.string("seal")),
    #("reason", json.string(r.reason)),
    #("kek_chain_order", json.array(["tpm", "passphrase", "kms"], json.string)),
    #("kdf", json.string("argon2id")),
    #("kdf_memory_mb", json.int(64)),
    #("kdf_iterations", json.int(3)),
    #("kdf_parallelism", json.int(4)),
    #("salt_min_bytes", json.int(16)),
    #("derived_key_bytes", json.int(32)),
    #("secret_material_read", json.bool(False)),
    #("execute", json.string("unavailable:" <> backend)),
    #(
      "unavailable_reason",
      json.string("sealing requires an opened vault and production authority"),
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
      json.string("sealing requires an opened vault and production authority"),
    ),
    #("authority", json.string("NONE")),
  ])
}

/// Never seals anything and never creates a file. A missing evidence_dir is
/// still an Error, so the service cannot mistake the refusal for a receipt.
pub fn execute(_r: Request, evidence_dir: String) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> Error("backend_unavailable:" <> backend)
    _ -> Error("evidence_dir_missing")
  }
}
