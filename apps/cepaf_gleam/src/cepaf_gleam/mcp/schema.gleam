//// Bounded JSON schema and argument validation for MCP tool calls.

import cepaf_gleam/harness/value.{type Value}
import cepaf_gleam/mcp/types.{type ToolError, NonRetryable, ToolError}
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

pub const max_schema_bytes = 262_144

pub const max_value_depth = 32

pub const max_local_ref_hops = 8

pub fn validate(schema: Json, args: Value) -> Result(Value, ToolError) {
  let raw_schema = json.to_string(schema)
  case string.byte_size(raw_schema) <= max_schema_bytes {
    False ->
      Error(ToolError(
        "SCHEMA_SIZE_EXCEEDED",
        "Schema exceeds 256 KiB bound",
        NonRetryable,
      ))
    True -> {
      use schema_val <- result.try(
        json.parse(raw_schema, value.decoder())
        |> result.replace_error(ToolError(
          "INVALID_SCHEMA_JSON",
          "Schema is not valid JSON",
          NonRetryable,
        )),
      )
      use _ <- result.try(check_schema_refs(schema_val, schema_val, 0))
      use _ <- result.try(check_value_depth(args, 0))
      use _ <- result.try(check_required_fields(schema_val, args))
      Ok(args)
    }
  }
}

fn check_value_depth(v: Value, depth: Int) -> Result(Nil, ToolError) {
  case depth > max_value_depth {
    True ->
      Error(ToolError(
        "ARGUMENT_DEPTH_EXCEEDED",
        "Arguments exceed maximum nesting depth 32",
        NonRetryable,
      ))
    False ->
      case v {
        value.Array(items) ->
          list.try_each(items, fn(item) { check_value_depth(item, depth + 1) })
        value.Object(fields) ->
          list.try_each(fields, fn(pair) {
            check_value_depth(pair.1, depth + 1)
          })
        _ -> Ok(Nil)
      }
  }
}

fn check_schema_refs(
  root: Value,
  current: Value,
  hops: Int,
) -> Result(Nil, ToolError) {
  case hops > max_local_ref_hops {
    True ->
      Error(ToolError(
        "SCHEMA_REF_CYCLE_OR_DEPTH",
        "Local schema reference exceeded max hops",
        NonRetryable,
      ))
    False ->
      case current {
        value.Object(fields) -> {
          use _ <- result.try(case value.get(current, "$ref") {
            Ok(value.Text(ref_target)) ->
              resolve_local_ref(root, ref_target, hops + 1)
            Ok(_) ->
              Error(ToolError(
                "INVALID_SCHEMA_REF",
                "$ref must be a string",
                NonRetryable,
              ))
            Error(_) -> Ok(Nil)
          })
          list.try_each(fields, fn(pair) {
            case pair.0 == "$defs" || pair.0 == "definitions" {
              True -> Ok(Nil)
              False -> check_schema_refs(root, pair.1, hops)
            }
          })
        }
        value.Array(items) ->
          list.try_each(items, fn(item) { check_schema_refs(root, item, hops) })
        _ -> Ok(Nil)
      }
  }
}

fn resolve_local_ref(
  root: Value,
  ref_target: String,
  hops: Int,
) -> Result(Nil, ToolError) {
  case
    string.starts_with(ref_target, "http://")
    || string.starts_with(ref_target, "https://")
    || !string.starts_with(ref_target, "#/")
  {
    True ->
      Error(ToolError(
        "REMOTE_SCHEMA_REF_FORBIDDEN",
        "Remote or non-local schema reference is forbidden: " <> ref_target,
        NonRetryable,
      ))
    False -> {
      let segments =
        ref_target
        |> string.drop_start(2)
        |> string.split("/")
      use target <- result.try(follow_segments(root, segments))
      check_schema_refs(root, target, hops)
    }
  }
}

fn follow_segments(
  current: Value,
  segments: List(String),
) -> Result(Value, ToolError) {
  case segments {
    [] -> Ok(current)
    [head, ..tail] ->
      case value.get(current, head) {
        Ok(next) -> follow_segments(next, tail)
        Error(_) ->
          Error(ToolError(
            "UNRESOLVED_LOCAL_REF",
            "Missing local schema reference segment: " <> head,
            NonRetryable,
          ))
      }
  }
}

fn check_required_fields(schema: Value, args: Value) -> Result(Nil, ToolError) {
  case value.get(schema, "required") {
    Ok(value.Array(req_items)) ->
      case args {
        value.Object(_) ->
          list.try_each(req_items, fn(req_item) {
            case req_item {
              value.Text(key) ->
                case value.get(args, key) {
                  Ok(_) -> Ok(Nil)
                  Error(_) ->
                    Error(ToolError(
                      "MISSING_REQUIRED_ARGUMENT",
                      "Missing required argument: " <> key,
                      NonRetryable,
                    ))
                }
              _ -> Ok(Nil)
            }
          })
        _ ->
          Error(ToolError(
            "OBJECT_ARGUMENTS_REQUIRED",
            "Tool arguments must be a JSON object",
            NonRetryable,
          ))
      }
    _ -> Ok(Nil)
  }
}
