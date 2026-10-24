//// Immutable public action profile; expected digest/context come from the trusted launcher.
//// Historical load grants no authority. Recheck and live effect fences remain mandatory.
//// Files use the existing cooperative parent-rename/same-UID boundary.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/list
import gleam/result
import gleam/string

const schema_version = "uos.telegram.action-profile.v1"

const max_raw_bytes = 16_384

const max_path_bytes = 4096

const max_token_bytes = 240

const max_bot_id = 9_007_199_254_740_991

const max_i32 = 2_147_483_647

const max_timestamp_ns = 9_223_372_036_854_775_807

const ns_per_ms = 1_000_000

pub type Context {
  Context(
    bot: Int,
    plan: String,
    task: String,
    worker: String,
    attempt: Int,
    epoch: Int,
    service_epoch: Int,
    candidate: String,
    host: String,
    boot: String,
  )
}

pub opaque type Profile {
  Profile(
    root: String,
    relative: String,
    digest: String,
    context: Context,
    request: bridge.Request,
    roster: approval.Roster,
    transport: transport.LocalConfiguration,
    roster_loaded_ms: Int,
    roster_expires_ms: Int,
  )
}

type Parsed {
  Parsed(
    digest: String,
    context: Context,
    request: bridge.Request,
    roster: approval.Roster,
    transport: transport.LocalConfiguration,
    roster_loaded_ms: Int,
    roster_expires_ms: Int,
  )
}

pub fn load(
  root: String,
  relative: String,
  expected_digest: String,
  expected_context: Context,
) -> Result(Profile, String) {
  use _ <- result.try(validate_digest(expected_digest))
  use _ <- result.try(validate_context(expected_context))
  use raw <- result.try(
    files.read(root, relative) |> result.map_error(fn(_) { "profile_invalid" }),
  )
  use parsed <- result.try(parse(raw, expected_digest, expected_context))
  Ok(Profile(
    root: root,
    relative: relative,
    digest: parsed.digest,
    context: parsed.context,
    request: parsed.request,
    roster: parsed.roster,
    transport: parsed.transport,
    roster_loaded_ms: parsed.roster_loaded_ms,
    roster_expires_ms: parsed.roster_expires_ms,
  ))
}

pub fn persist(
  root: String,
  relative: String,
  raw: String,
  expected_digest: String,
  expected_context: Context,
) -> Result(Profile, String) {
  use _ <- result.try(parse(raw, expected_digest, expected_context))
  use _ <- result.try(
    files.create(root, relative, raw)
    |> result.map_error(fn(_) { "profile_invalid" }),
  )
  load(root, relative, expected_digest, expected_context)
}

pub fn recheck(
  p: Profile,
  expected_context: Context,
  now_ns: Int,
) -> Result(Profile, String) {
  use current <- result.try(load(p.root, p.relative, p.digest, expected_context))
  case active_at(current, expected_context, now_ns) {
    True -> Ok(current)
    False -> Error("profile_not_active")
  }
}

pub fn active_at(p: Profile, expected_context: Context, now_ns: Int) -> Bool {
  expected_context == p.context
  && now_ns >= 0
  && now_ns <= max_timestamp_ns
  && now_ns >= p.roster_loaded_ms * ns_per_ms
  && now_ns < p.roster_expires_ms * ns_per_ms
  && now_ns < bridge.expires_at_ns(p.request)
}

pub fn request(p: Profile) -> bridge.Request {
  p.request
}

pub fn roster(p: Profile) -> approval.Roster {
  p.roster
}

pub fn transport(p: Profile) -> transport.LocalConfiguration {
  p.transport
}

pub fn digest(p: Profile) -> String {
  p.digest
}

pub fn context(p: Profile) -> Context {
  p.context
}

fn parse(
  raw: String,
  expected_digest: String,
  expected_context: Context,
) -> Result(Parsed, String) {
  use _ <- result.try(validate_digest(expected_digest))
  use _ <- result.try(validate_context(expected_context))
  let raw_size = string.byte_size(raw)
  use _ <- result.try(
    case
      raw_size > 0
      && raw_size <= max_raw_bytes
      && files.digest(raw) == expected_digest
    {
      True -> Ok(Nil)
      False -> Error("profile_invalid")
    },
  )
  use json <- result.try(
    codec.parse_strict_json(raw)
    |> result.map_error(fn(_) { "profile_invalid" }),
  )
  use #(schema_val, context_val, provision_val, transport_val, roster_val) <- result.try(
    extract_closed_object(json),
  )
  use _ <- result.try(parse_schema(schema_val))
  use parsed_context <- result.try(parse_context(context_val, expected_context))
  use prov_request <- result.try(parse_provision(provision_val, parsed_context))
  use local_transport <- result.try(parse_transport(transport_val))
  use #(loaded_ms, expires_ms, signer_roster) <- result.try(parse_roster(
    roster_val,
  ))
  Ok(Parsed(
    digest: expected_digest,
    context: parsed_context,
    request: prov_request,
    roster: signer_roster,
    transport: local_transport,
    roster_loaded_ms: loaded_ms,
    roster_expires_ms: expires_ms,
  ))
}

fn extract_closed_object(
  value: codec.StrictJsonValue,
) -> Result(
  #(
    codec.StrictJsonValue,
    codec.StrictJsonValue,
    codec.StrictJsonValue,
    codec.StrictJsonValue,
    codec.StrictJsonValue,
  ),
  String,
) {
  case value {
    codec.JsonObject(fields) ->
      case list.length(fields) == 5 {
        True -> {
          use schema_val <- result.try(find_unique_field(fields, "schema"))
          use context_val <- result.try(find_unique_field(fields, "context"))
          use provision_val <- result.try(find_unique_field(
            fields,
            "provision_json",
          ))
          use transport_val <- result.try(find_unique_field(fields, "transport"))
          use roster_val <- result.try(find_unique_field(fields, "roster"))
          Ok(#(
            schema_val,
            context_val,
            provision_val,
            transport_val,
            roster_val,
          ))
        }
        False -> Error("profile_invalid")
      }
    _ -> Error("profile_invalid")
  }
}

fn find_unique_field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(codec.StrictJsonValue, String) {
  let matches =
    list.filter(fields, fn(entry) {
      let #(k, _) = entry
      k == key
    })
  case matches {
    [#(_, val)] -> Ok(val)
    _ -> Error("profile_invalid")
  }
}

fn parse_schema(value: codec.StrictJsonValue) -> Result(Nil, String) {
  case value {
    codec.JsonString(s) if s == schema_version -> Ok(Nil)
    _ -> Error("profile_invalid")
  }
}

fn parse_context(
  value: codec.StrictJsonValue,
  expected_context: Context,
) -> Result(Context, String) {
  case value {
    codec.JsonArray([
      codec.JsonInt(bot),
      codec.JsonString(plan),
      codec.JsonString(task),
      codec.JsonString(worker),
      codec.JsonInt(attempt),
      codec.JsonInt(epoch),
      codec.JsonInt(service_epoch),
      codec.JsonString(candidate),
      codec.JsonString(host),
      codec.JsonString(boot),
    ]) -> {
      let ctx =
        Context(
          bot: bot,
          plan: plan,
          task: task,
          worker: worker,
          attempt: attempt,
          epoch: epoch,
          service_epoch: service_epoch,
          candidate: candidate,
          host: host,
          boot: boot,
        )
      case ctx == expected_context {
        True -> {
          use _ <- result.try(validate_context(ctx))
          Ok(ctx)
        }
        False -> Error("profile_invalid")
      }
    }
    _ -> Error("profile_invalid")
  }
}

fn validate_context(ctx: Context) -> Result(Nil, String) {
  let valid_numbers =
    ctx.bot >= 1
    && ctx.bot <= max_bot_id
    && ctx.attempt >= 1
    && ctx.attempt <= max_i32
    && ctx.epoch >= 1
    && ctx.epoch <= max_i32
    && ctx.service_epoch >= 1
    && ctx.service_epoch <= max_i32
  let valid_host =
    string.byte_size(ctx.host) > 7
    && string.ends_with(ctx.host, ".ts.net")
    && is_valid_token(ctx.host)
  let valid_tokens =
    is_valid_token(ctx.plan)
    && is_valid_token(ctx.task)
    && is_valid_token(ctx.worker)
    && is_valid_token(ctx.boot)
    && is_valid_sha256(ctx.candidate)
  case valid_numbers && valid_host && valid_tokens {
    True -> {
      use _ <- result.try(
        bridge.new(
          "context",
          ctx.plan,
          ctx.task,
          ctx.worker,
          ctx.attempt,
          ctx.boot,
          1,
        )
        |> result.map_error(fn(_) { "profile_invalid" }),
      )
      use _ <- result.try(
        bridge.new(
          ctx.host,
          ctx.plan,
          ctx.task,
          ctx.worker,
          ctx.attempt,
          ctx.boot,
          1,
        )
        |> result.map_error(fn(_) { "profile_invalid" }),
      )
      Ok(Nil)
    }
    False -> Error("profile_invalid")
  }
}

fn parse_provision(
  value: codec.StrictJsonValue,
  ctx: Context,
) -> Result(bridge.Request, String) {
  case value {
    codec.JsonString(raw_provision) -> {
      use req <- result.try(
        bridge.restore(raw_provision)
        |> result.map_error(fn(_) { "profile_invalid" }),
      )
      case
        bridge.matches_context(req, ctx.plan, ctx.task, ctx.worker, ctx.attempt)
      {
        True -> Ok(req)
        False -> Error("profile_invalid")
      }
    }
    _ -> Error("profile_invalid")
  }
}

fn parse_transport(
  value: codec.StrictJsonValue,
) -> Result(transport.LocalConfiguration, String) {
  case value {
    codec.JsonArray([
      codec.JsonString(guardian_path),
      codec.JsonString(guardian_sha),
      codec.JsonString(worker_path),
      codec.JsonString(worker_sha),
      codec.JsonString(db_path),
    ]) ->
      case
        is_valid_absolute_path(guardian_path)
        && is_valid_sha256(guardian_sha)
        && is_valid_absolute_path(worker_path)
        && is_valid_sha256(worker_sha)
        && is_valid_absolute_path(db_path)
      {
        True ->
          Ok(transport.reviewed_local_configuration(
            guardian_path,
            guardian_sha,
            worker_path,
            worker_sha,
            db_path,
          ))
        False -> Error("profile_invalid")
      }
    _ -> Error("profile_invalid")
  }
}

fn parse_roster(
  value: codec.StrictJsonValue,
) -> Result(#(Int, Int, approval.Roster), String) {
  case value {
    codec.JsonArray([
      codec.JsonInt(loaded_at_ms),
      codec.JsonInt(expires_at_ms),
      codec.JsonArray(raw_signers),
    ]) -> {
      let count = list.length(raw_signers)
      case count >= 3 && count <= 4 {
        True -> {
          use signers <- result.try(list.try_map(raw_signers, parse_signer))
          use signer_roster <- result.try(
            approval.new_roster(signers, loaded_at_ms, expires_at_ms)
            |> result.map_error(fn(_) { "profile_invalid" }),
          )
          Ok(#(loaded_at_ms, expires_at_ms, signer_roster))
        }
        False -> Error("profile_invalid")
      }
    }
    _ -> Error("profile_invalid")
  }
}

fn parse_signer(
  value: codec.StrictJsonValue,
) -> Result(approval.Signer, String) {
  case value {
    codec.JsonArray([
      codec.JsonString(role_str),
      codec.JsonString(subject),
      codec.JsonString(kid),
      codec.JsonString(public_key),
    ]) -> {
      use role <- result.try(parse_role(role_str))
      Ok(approval.Signer(
        role: role,
        subject: subject,
        kid: kid,
        public_key: public_key,
      ))
    }
    _ -> Error("profile_invalid")
  }
}

fn parse_role(value: String) -> Result(approval.Role, String) {
  case value {
    "codex" -> Ok(approval.Codex)
    "agy" -> Ok(approval.Agy)
    "claude" -> Ok(approval.Claude)
    "operator" -> Ok(approval.Operator)
    _ -> Error("profile_invalid")
  }
}

fn validate_digest(value: String) -> Result(Nil, String) {
  case is_valid_sha256(value) {
    True -> Ok(Nil)
    False -> Error("profile_invalid")
  }
}

fn is_valid_sha256(value: String) -> Bool {
  string.byte_size(value) == 64
  && list.all(string.to_utf_codepoints(value), fn(cp) {
    let code = string.utf_codepoint_to_int(cp)
    { code >= 48 && code <= 57 } || { code >= 97 && code <= 102 }
  })
}

fn is_valid_token(value: String) -> Bool {
  let size = string.byte_size(value)
  size >= 1
  && size <= max_token_bytes
  && !string.contains(value, "..")
  && list.all(string.to_utf_codepoints(value), fn(cp) {
    let code = string.utf_codepoint_to_int(cp)
    code >= 33 && code <= 126
  })
}

fn is_valid_absolute_path(path: String) -> Bool {
  let size = string.byte_size(path)
  let valid_chars =
    list.all(string.to_utf_codepoints(path), fn(cp) {
      let code = string.utf_codepoint_to_int(cp)
      code >= 32 && code != 127 && code != 92
    })
  case
    size >= 2 && size <= max_path_bytes && valid_chars,
    string.split(path, "/")
  {
    True, ["", ..segments] ->
      segments != []
      && list.all(segments, fn(seg) { seg != "" && seg != "." && seg != ".." })
    _, _ -> False
  }
}
