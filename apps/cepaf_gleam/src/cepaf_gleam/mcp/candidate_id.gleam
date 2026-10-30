//// Canonical candidate identity for the MCP harness.
////
//// The candidate id is derived from the exact bytes of the core MCP source
//// files so that completion evidence can never name a generic or stale
//// candidate. Reads are attempted relative to the Gleam project root and the
//// monorepo app root under an explicit workspace root; there is no hardcoded
//// absolute fallback, so an unrecognized working directory fails closed to
//// `UNOBSERVED_CANDIDATE_SOURCE` rather than silently naming another checkout.

import cepaf_gleam/harness/files
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile

const core_source_paths = [
  "mcp/registry.gleam",
  "mcp/admission.gleam",
  "mcp/receipts.gleam",
  "mcp/dispatch.gleam",
  "mcp/route_convergence.gleam",
  "mcp/server.gleam",
]

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(key: String) -> Result(String, Nil)

fn read_core_source(root: String, rel: String) -> Result(String, Nil) {
  case simplifile.read(root <> "/src/cepaf_gleam/" <> rel) {
    Ok(content) -> Ok(content)
    Error(_) ->
      case
        simplifile.read(root <> "/apps/cepaf_gleam/src/cepaf_gleam/" <> rel)
      {
        Ok(content) -> Ok(content)
        Error(_) -> Error(Nil)
      }
  }
}

pub fn from_root(root: String) -> String {
  let trimmed = string.trim(root)
  case trimmed {
    "" -> "UNOBSERVED_CANDIDATE_SOURCE"
    _ -> {
      let contents =
        list.map(core_source_paths, fn(rel) { read_core_source(trimmed, rel) })
      case result.all(contents) {
        Error(_) -> "UNOBSERVED_CANDIDATE_SOURCE"
        Ok(files_content) -> {
          let framed =
            list.zip(core_source_paths, files_content)
            |> list.map(fn(pair) {
              let #(rel, content) = pair
              int.to_string(string.byte_size(rel))
              <> ":"
              <> rel
              <> "|"
              <> int.to_string(string.byte_size(content))
              <> ":"
              <> content
              <> "|"
            })
            |> string.concat
          "sha256:" <> files.digest(framed)
        }
      }
    }
  }
}

pub fn current() -> String {
  case get_env("UOS_MCP_WORKSPACE_ROOT") {
    Ok(explicit) -> {
      let trimmed = string.trim(explicit)
      case trimmed {
        "" -> from_root(".")
        _ -> from_root(trimmed)
      }
    }
    Error(_) -> from_root(".")
  }
}

pub fn is_sha256_digest(candidate: String) -> Bool {
  let trimmed = string.trim(candidate)
  string.starts_with(trimmed, "sha256:")
  && string.byte_size(trimmed) == 71
  && {
    string.drop_start(trimmed, 7)
    |> string.to_graphemes
    |> list.all(fn(grapheme) { string.contains("0123456789abcdef", grapheme) })
  }
}

/// `is_valid` is the coarse label gate used by
/// `start_worker_pool_for_candidate`; it intentionally permits explicit
/// unit-test fixture candidate labels (for example `"foreign-candidate"`) while
/// still rejecting empty, generic, and unobserved labels. Live six-source
/// SHA-256 digests are validated strictly by `is_sha256_digest`, and
/// `start_worker_pool` requires the latter.
pub fn is_valid(candidate: String) -> Bool {
  let trimmed = string.trim(candidate)
  case trimmed {
    "" -> False
    "uos-mcp" -> False
    "uos-mcp-candidate" -> False
    "UNOBSERVED_CANDIDATE_SOURCE" -> False
    "unknown" -> False
    "default" -> False
    _ -> True
  }
}
