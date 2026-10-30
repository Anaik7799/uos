//// T10 Knowledge & File Family Adapter: knowledge_search, read_file,
//// zk_search, zk_transclude. Enforces strict path, credential, link-escape,
//// scope, size, and bounded transclusion guards before any content is served.

import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/types.{
  type Outcome, NonRetryable, Refused, type ToolError, ToolError,
}
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type LinkKind {
  RegularFile
  SymlinkEscape
  HardlinkEscape
}

pub type CorpusEntry {
  CorpusEntry(
    rel_path: String,
    link_kind: LinkKind,
    scope_tag: String,
    content: String,
  )
}

pub type KnowledgeCorpus {
  KnowledgeCorpus(
    workspace_root: String,
    allowed_scopes: List(String),
    max_bytes: Int,
    max_transclude_depth: Int,
    entries: Dict(String, CorpusEntry),
  )
}

pub const credential_markers = [
  ".env",
  ".ssh",
  "id_rsa",
  "id_ed25519",
  "id_ecdsa",
  "credentials",
  "secret",
  "oauth",
  ".sqlite3-wal",
  ".sqlite3-shm",
  ".sqlite3",
  ".pem",
  ".key",
  ".netrc",
  "token",
  "password",
]

pub fn new_corpus(
  workspace_root: String,
  allowed_scopes: List(String),
  max_bytes: Int,
  max_transclude_depth: Int,
) -> KnowledgeCorpus {
  KnowledgeCorpus(
    workspace_root: workspace_root,
    allowed_scopes: allowed_scopes,
    max_bytes: max_bytes,
    max_transclude_depth: max_transclude_depth,
    entries: dict.new(),
  )
}

pub fn with_entry(
  corpus: KnowledgeCorpus,
  entry: CorpusEntry,
) -> KnowledgeCorpus {
  KnowledgeCorpus(
    ..corpus,
    entries: dict.insert(corpus.entries, entry.rel_path, entry),
  )
}

/// Returns a human-readable reason when a path must be refused, otherwise None.
pub fn path_security_violation(
  path: String,
  workspace_root: String,
) -> Option(String) {
  case string.contains(path, "..") {
    True -> Some("path traversal segment or sequence is forbidden")
    False ->
      case string.contains(path, "\u{0000}") {
        True -> Some("NUL byte in path is forbidden")
        False -> {
          let inside_workspace =
            path == workspace_root
            || string.starts_with(path, workspace_root <> "/")
          case string.starts_with(path, "/") && !inside_workspace {
            True -> Some("absolute path outside workspace_root is forbidden")
            False -> {
              let lowered = string.lowercase(path)
              case
                list.find(credential_markers, fn(marker) {
                  string.contains(lowered, marker)
                })
              {
                Ok(marker) ->
                  Some("credential or WAL segment is forbidden: " <> marker)
                Error(_) -> None
              }
            }
          }
        }
      }
  }
}

pub fn execute(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  case tool_name {
    "knowledge_search" -> search(corpus, principal_scopes, args, False)
    "read_file" -> read_file(corpus, principal_scopes, args)
    "zk_search" -> search(corpus, principal_scopes, args, True)
    "zk_transclude" -> transclude(corpus, principal_scopes, args)
    _ ->
      Refused(ToolError(
        code: "UNSUPPORTED_KNOWLEDGE_TOOL",
        reason: "Unsupported tool in knowledge adapter: " <> tool_name,
        retryability: NonRetryable,
      ))
  }
}

fn guard_path(
  corpus: KnowledgeCorpus,
  path: String,
) -> Result(Nil, ToolError) {
  case path_security_violation(path, corpus.workspace_root) {
    Some(reason) ->
      Error(ToolError(
        code: "PATH_SECURITY_VIOLATION",
        reason: reason,
        retryability: NonRetryable,
      ))
    None -> Ok(Nil)
  }
}

fn lookup_entry(
  corpus: KnowledgeCorpus,
  path: String,
) -> Result(CorpusEntry, ToolError) {
  case dict.get(corpus.entries, path) {
    Ok(entry) -> Ok(entry)
    Error(_) ->
      Error(ToolError(
        code: "PATH_NOT_IN_CORPUS",
        reason: "No corpus entry for " <> path,
        retryability: NonRetryable,
      ))
  }
}

fn guard_entry(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  path: String,
  entry: CorpusEntry,
) -> Result(Nil, ToolError) {
  use _ <- result.try(guard_path(corpus, path))
  case entry.link_kind {
    SymlinkEscape | HardlinkEscape ->
      Error(ToolError(
        code: "LINK_ESCAPE_REFUSED",
        reason: "Refused link escape at " <> entry.rel_path,
        retryability: NonRetryable,
      ))
    RegularFile ->
      case
        list.contains(corpus.allowed_scopes, entry.scope_tag)
        && list.contains(principal_scopes, entry.scope_tag)
      {
        True -> Ok(Nil)
        False ->
          Error(ToolError(
            code: "CROSS_PRINCIPAL_SCOPE_FORBIDDEN",
            reason: "Principal scope cannot expand to " <> entry.scope_tag,
            retryability: NonRetryable,
          ))
      }
  }
}

fn read_file(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  args: Dict(String, String),
) -> Outcome {
  let path = dict.get(args, "path") |> result.unwrap("")
  case guard_path(corpus, path) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case lookup_entry(corpus, path) {
        Error(error) -> Refused(error)
        Ok(entry) ->
          case guard_entry(corpus, principal_scopes, path, entry) {
            Error(error) -> Refused(error)
            Ok(_) ->
              case string.byte_size(entry.content) <= corpus.max_bytes {
                False ->
                  Refused(ToolError(
                    code: "FILE_SIZE_BOUND_EXCEEDED",
                    reason: "Corpus entry exceeds max_bytes bound",
                    retryability: NonRetryable,
                  ))
                True ->
                  evidence.classify_backend_payload(
                    "public",
                    "read_file",
                    entry.content,
                    "uos-mcp",
                  )
              }
          }
      }
  }
}

fn is_zk_entry(entry: CorpusEntry) -> Bool {
  string.contains(string.lowercase(entry.scope_tag), "zk")
  || string.contains(string.lowercase(entry.rel_path), "zk")
}

fn searchable(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  entry: CorpusEntry,
  zk_only: Bool,
) -> Bool {
  case path_security_violation(entry.rel_path, corpus.workspace_root) {
    Some(_) -> False
    None ->
      case entry.link_kind {
        RegularFile -> {
          let zk_ok = !zk_only || is_zk_entry(entry)
          list.contains(corpus.allowed_scopes, entry.scope_tag)
          && list.contains(principal_scopes, entry.scope_tag)
          && zk_ok
        }
        SymlinkEscape | HardlinkEscape -> False
      }
  }
}

fn search(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  args: Dict(String, String),
  zk_only: Bool,
) -> Outcome {
  let query = dict.get(args, "query") |> result.unwrap("")
  let lowered = string.lowercase(query)
  let matches =
    corpus.entries
    |> dict.values
    |> list.filter(fn(entry) { searchable(corpus, principal_scopes, entry, zk_only) })
    |> list.filter(fn(entry) {
      string.contains(string.lowercase(entry.content), lowered)
    })
  let tool_name = case zk_only {
    True -> "zk_search"
    False -> "knowledge_search"
  }
  let payload =
    json.to_string(json.object([
      #("query", json.string(query)),
      #("results", json.array(matches, encode_entry)),
    ]))
  evidence.classify_backend_payload("public", tool_name, payload, "uos-mcp")
}

fn encode_entry(entry: CorpusEntry) -> json.Json {
  json.object([
    #("rel_path", json.string(entry.rel_path)),
    #("scope_tag", json.string(entry.scope_tag)),
    #("content", json.string(entry.content)),
  ])
}

fn cycle_or_depth_refusal() -> ToolError {
  ToolError(
    code: "TRANSCLUSION_CYCLE_OR_DEPTH_EXCEEDED",
    reason: "Transclusion cycle detected or max depth exceeded",
    retryability: NonRetryable,
  )
}

fn transclude(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  args: Dict(String, String),
) -> Outcome {
  let key = case dict.get(args, "key") {
    Ok(value) if value != "" -> value
    _ -> dict.get(args, "query") |> result.unwrap("")
  }
  case expand_entry(corpus, principal_scopes, key, [], 0) {
    Error(error) -> Refused(error)
    Ok(expanded) ->
      evidence.classify_backend_payload(
        "public",
        "zk_transclude",
        expanded,
        "uos-mcp",
      )
  }
}

fn expand_entry(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  key: String,
  visited: List(String),
  depth: Int,
) -> Result(String, ToolError) {
  case depth > corpus.max_transclude_depth {
    True -> Error(cycle_or_depth_refusal())
    False ->
      case list.contains(visited, key) {
        True -> Error(cycle_or_depth_refusal())
        False -> {
          use entry <- result.try(lookup_entry(corpus, key))
          use _ <- result.try(guard_entry(corpus, principal_scopes, key, entry))
          expand_references(
            corpus,
            principal_scopes,
            entry.content,
            [key, ..visited],
            depth,
          )
        }
      }
  }
}

fn expand_references(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  content: String,
  visited: List(String),
  depth: Int,
) -> Result(String, ToolError) {
  expand_references_loop(
    corpus,
    principal_scopes,
    content,
    visited,
    depth,
    "",
  )
}

fn expand_references_loop(
  corpus: KnowledgeCorpus,
  principal_scopes: List(String),
  remaining: String,
  visited: List(String),
  depth: Int,
  acc: String,
) -> Result(String, ToolError) {
  case string.split_once(remaining, "[[") {
    Error(_) -> Ok(acc <> remaining)
    Ok(#(before, rest)) ->
      case string.split_once(rest, "]]") {
        Error(_) -> Ok(acc <> before <> "[[" <> rest)
        Ok(#(tag_content, after)) -> {
          let reference = case string.split_once(tag_content, ":") {
            Ok(#("zk", ref)) -> Ok(ref)
            Ok(#("wiki", ref)) -> Ok(ref)
            _ -> Error(Nil)
          }
          case reference {
            Error(_) ->
              expand_references_loop(
                corpus,
                principal_scopes,
                after,
                visited,
                depth,
                acc <> before <> "[[" <> tag_content <> "]]",
              )
            Ok(ref) -> {
              use expanded <- result.try(
                expand_entry(corpus, principal_scopes, ref, visited, depth + 1),
              )
              expand_references_loop(
                corpus,
                principal_scopes,
                after,
                visited,
                depth,
                acc <> before <> expanded,
              )
            }
          }
        }
      }
  }
}
