//// T17 principal-partitioned MCP resources. Pagination is bounded, `uos://`
//// URIs are validated strictly, and both the visibility/ownership checks and
//// the cache key are bound to the transport-derived principal. A private
//// resource cached by principal A can never be read from principal B's cache
//// entry.

import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{type ToolError, NonRetryable, ToolError}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

pub const max_cache_entries = 1024

pub const page_default = 100

pub const page_max = 500

pub const credential_markers = [".env", ".ssh", ".sqlite3", ".key", ".pem"]

pub type ResourceVisibility {
  PublicResource
  PrivatePrincipalResource
}

pub type ResourceEntry {
  ResourceEntry(
    uri: String,
    title: String,
    mime_type: String,
    visibility: ResourceVisibility,
    owner_actor: String,
    workspace_root: String,
    content: String,
  )
}

pub type ResourceTemplate {
  ResourceTemplate(uri_template: String, name: String, description: String)
}

pub type ResourceRegistry {
  ResourceRegistry(
    resources: List(ResourceEntry),
    templates: List(ResourceTemplate),
  )
}

pub type ResourceCache {
  ResourceCache(entries: Dict(#(String, String, String), ResourceEntry))
}

pub fn registry(
  resources: List(ResourceEntry),
  templates: List(ResourceTemplate),
) -> ResourceRegistry {
  ResourceRegistry(resources, templates)
}

pub fn empty_cache() -> ResourceCache {
  ResourceCache(dict.new())
}

/// Strict `uos://` only. Rejects foreign schemes, traversal, NUL, and any URI
/// that appears to reference a credential-bearing file.
pub fn validate_uri(uri: String) -> Result(Nil, ToolError) {
  case string.starts_with(uri, "uos://") {
    False -> Error(invalid_uri(uri))
    True ->
      case
        string.contains(uri, "..")
        || string.contains(uri, "\u{0000}")
        || has_credential_marker(uri)
      {
        True -> Error(invalid_uri(uri))
        False -> Ok(Nil)
      }
  }
}

fn has_credential_marker(uri: String) -> Bool {
  list.any(credential_markers, fn(marker) { string.contains(uri, marker) })
}

fn invalid_uri(uri: String) -> ToolError {
  ToolError(
    "INVALID_RESOURCE_URI",
    "Rejected resource URI: " <> uri,
    NonRetryable,
  )
}

fn check_page_limit(limit: Int) -> Result(Nil, ToolError) {
  case limit <= 0 || limit > page_max {
    True ->
      Error(ToolError(
        "INVALID_PAGE_LIMIT",
        "Page limit must be between 1 and " <> string.inspect(page_max),
        NonRetryable,
      ))
    False -> Ok(Nil)
  }
}

fn cache_key(principal: Principal, uri: String) -> #(String, String, String) {
  #(principal.actor_id(principal), principal.workspace_root(principal), uri)
}

/// Workspace match is enforced for every entry. A `PrivatePrincipalResource`
/// additionally requires the transport-bound owner_actor to equal the
/// principal actor.
pub fn authorize_entry(
  principal: Principal,
  entry: ResourceEntry,
) -> Result(Nil, ToolError) {
  case entry.workspace_root == principal.workspace_root(principal) {
    False ->
      Error(ToolError(
        "PRINCIPAL_WORKSPACE_MISMATCH",
        "Resource " <> entry.uri <> " is outside the principal workspace",
        NonRetryable,
      ))
    True ->
      case entry.visibility {
        PrivatePrincipalResource ->
          case entry.owner_actor == principal.actor_id(principal) {
            False ->
              Error(ToolError(
                "CROSS_PRINCIPAL_RESOURCE_FORBIDDEN",
                "Private resource "
                  <> entry.uri
                  <> " belongs to another principal",
                NonRetryable,
              ))
            True -> Ok(Nil)
          }
        PublicResource -> Ok(Nil)
      }
  }
}

fn is_authorized(principal: Principal, entry: ResourceEntry) -> Bool {
  case authorize_entry(principal, entry) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn cache_entry(
  cache: ResourceCache,
  principal: Principal,
  entry: ResourceEntry,
) -> ResourceCache {
  let key = cache_key(principal, entry.uri)
  case
    dict.has_key(cache.entries, key)
    || dict.size(cache.entries) < max_cache_entries
  {
    True -> ResourceCache(dict.insert(cache.entries, key, entry))
    False -> cache
  }
}

pub fn list_resources(
  registry: ResourceRegistry,
  cache: ResourceCache,
  principal: Principal,
  limit: Int,
  offset: Int,
) -> Result(#(List(ResourceEntry), ResourceCache), ToolError) {
  use _ <- result.try(check_page_limit(limit))
  let authorized =
    list.filter(registry.resources, fn(entry) {
      is_authorized(principal, entry)
    })
  let page = authorized |> list.drop(offset) |> list.take(limit)
  let updated =
    list.fold(page, cache, fn(acc, entry) { cache_entry(acc, principal, entry) })
  Ok(#(page, updated))
}

pub fn list_templates(
  registry: ResourceRegistry,
  principal: Principal,
) -> Result(List(ResourceTemplate), ToolError) {
  case principal.workspace_root(principal) == "" {
    True ->
      Error(ToolError(
        "PRINCIPAL_WORKSPACE_MISMATCH",
        "Principal has no workspace root for resource templates",
        NonRetryable,
      ))
    False -> Ok(registry.templates)
  }
}

pub fn read_resource(
  registry: ResourceRegistry,
  cache: ResourceCache,
  principal: Principal,
  uri: String,
) -> Result(#(ResourceEntry, ResourceCache), ToolError) {
  use _ <- result.try(validate_uri(uri))
  case list.find(registry.resources, fn(entry) { entry.uri == uri }) {
    Error(_) ->
      Error(ToolError(
        "RESOURCE_NOT_FOUND",
        "No resource registered for URI " <> uri,
        NonRetryable,
      ))
    Ok(entry) -> {
      // Ownership/workspace checks happen BEFORE the cache is consulted or
      // populated, so a foreign principal can never observe a cached private
      // resource.
      use _ <- result.try(authorize_entry(principal, entry))
      case dict.get(cache.entries, cache_key(principal, uri)) {
        Ok(cached) -> Ok(#(cached, cache))
        Error(_) -> Ok(#(entry, cache_entry(cache, principal, entry)))
      }
    }
  }
}
