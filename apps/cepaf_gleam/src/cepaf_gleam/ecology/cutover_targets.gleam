//// Pure OI02 logical target inventory from the canonical master handover,
//// table lines143..156. Four repository + seven home configurations and three
//// runtime targets. Fourteen LOGICAL targets is not fourteen physical files.
//// No filesystem, network, actors, dispatch, cutover or release authority.
//// Root mapping is lexical only; symlink/inode checks and effect-time authority
//// belong to the existing packager. Unknown environment mapping fails closed.

import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type TargetId {
  WorkspaceClaudeMcp
  WorkspaceCodexConfig
  WorkspaceAgySettings
  WorkspacePiMcp
  ReleasePointer
  CockpitService
  EcologyComponent
  HomeAgyAntigravityMcp
  HomeAgyConfigMcp
  HomeAgySettings
  HomeCodexConfig
  HomeClaudeConfig
  HomePiMcp
  HomePiMcpAdapter
}

pub type Owner {
  Claude
  Codex
  Agy
  Pi
  EcologyRuntime
  CockpitRuntime
}

pub type EnvironmentLocator {
  UnresolvedEnvironment
}

pub type Locator {
  RepositoryRelative(String)
  HomeRelative(String)
  EcologyUnitEnvironmentGroup(EnvironmentLocator)
}

pub type Target {
  Target(id: TargetId, owner: Owner, locator: Locator)
}

pub type Error {
  DuplicateTarget(TargetId)
  MissingTargets(List(TargetId))
  WrongCardinality(expected: Int, actual: Int)
  TargetMismatch(TargetId)
  UnsafeLocator(TargetId)
  InvalidRoot
  AliasedRoots
  AliasedMapping
  MappingTooLong
  UnknownEnvironment(TargetId)
}

pub opaque type Roots {
  Roots(repository: String, home: String)
}

pub type RootScope {
  RepositoryRoot
  HomeRoot
}

pub type MappedFile {
  MappedFile(
    id: TargetId,
    owner: Owner,
    scope: RootScope,
    relative: String,
    absolute: String,
  )
}

pub const logical_target_count = 14

pub const configuration_target_count = 11

pub const runtime_target_count = 3

fn ids() -> List(TargetId) {
  [
    WorkspaceClaudeMcp, WorkspaceCodexConfig, WorkspaceAgySettings,
    WorkspacePiMcp, ReleasePointer, CockpitService, EcologyComponent,
    HomeAgyAntigravityMcp, HomeAgyConfigMcp, HomeAgySettings, HomeCodexConfig,
    HomeClaudeConfig, HomePiMcp, HomePiMcpAdapter,
  ]
}

pub fn target(id: TargetId) -> Target {
  case id {
    WorkspaceClaudeMcp -> Target(id, Claude, RepositoryRelative(".mcp.json"))
    WorkspaceCodexConfig ->
      Target(id, Codex, RepositoryRelative(".codex/config.toml"))
    WorkspaceAgySettings ->
      Target(id, Agy, RepositoryRelative(".gemini/settings.json"))
    WorkspacePiMcp -> Target(id, Pi, RepositoryRelative(".pi/mcp.json"))
    ReleasePointer ->
      Target(
        id,
        EcologyRuntime,
        RepositoryRelative("var/releases/ecology/current-mcp-release"),
      )
    CockpitService ->
      Target(
        id,
        CockpitRuntime,
        HomeRelative(".config/systemd/user/c3i-gleam-server.service"),
      )
    EcologyComponent ->
      Target(
        id,
        EcologyRuntime,
        EcologyUnitEnvironmentGroup(UnresolvedEnvironment),
      )
    HomeAgyAntigravityMcp ->
      Target(id, Agy, HomeRelative(".gemini/antigravity-cli/mcp_config.json"))
    HomeAgyConfigMcp ->
      Target(id, Agy, HomeRelative(".gemini/config/mcp_config.json"))
    HomeAgySettings -> Target(id, Agy, HomeRelative(".gemini/settings.json"))
    HomeCodexConfig -> Target(id, Codex, HomeRelative(".codex/config.toml"))
    HomeClaudeConfig -> Target(id, Claude, HomeRelative(".claude.json"))
    HomePiMcp -> Target(id, Pi, HomeRelative(".pi/agent/mcp.json"))
    HomePiMcpAdapter ->
      Target(id, Pi, HomeRelative(".pi/agent/mcp-adapter.json"))
  }
}

pub fn canonical() -> List(Target) {
  list.map(ids(), target)
}

pub fn is_configuration(id: TargetId) -> Bool {
  case id {
    ReleasePointer | CockpitService | EcologyComponent -> False
    _ -> True
  }
}

fn characters(path: String) -> Bool {
  list.all(string.to_graphemes(path), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-",
      c,
    )
  })
}

fn safe_relative(path: String) -> Bool {
  string.byte_size(path) > 0
  && string.byte_size(path) <= 512
  && !string.starts_with(path, "/")
  && characters(path)
  && list.all(string.split(path, "/"), fn(part) {
    part != "" && part != "." && part != ".." && part != ".jj"
  })
}

fn safe_root(path: String) -> Bool {
  string.byte_size(path) > 1
  && string.byte_size(path) <= 4096
  && string.starts_with(path, "/")
  && characters(path)
  && list.all(list.drop(string.split(path, "/"), 1), fn(part) {
    part != "" && part != "." && part != ".." && part != ".jj"
  })
  && !list.any(["/proc", "/sys", "/dev"], fn(reserved) {
    path == reserved || string.starts_with(path, reserved <> "/")
  })
}

fn validate_target(row: Target) -> Result(Nil, Error) {
  let safe = case row.locator {
    RepositoryRelative(path) | HomeRelative(path) -> safe_relative(path)
    EcologyUnitEnvironmentGroup(UnresolvedEnvironment) -> True
  }
  case safe, row == target(row.id) {
    False, _ -> Error(UnsafeLocator(row.id))
    True, False -> Error(TargetMismatch(row.id))
    True, True -> Ok(Nil)
  }
}

fn check_unique(
  rows: List(Target),
  seen: List(TargetId),
) -> Result(Nil, Error) {
  case rows {
    [] -> Ok(Nil)
    [row, ..rest] ->
      case list.contains(seen, row.id) {
        True -> Error(DuplicateTarget(row.id))
        False -> check_unique(rest, [row.id, ..seen])
      }
  }
}

pub fn validate_inventory(rows: List(Target)) -> Result(Nil, Error) {
  // Bound before iteration; duplicate checks preserve explicit useful errors.
  case list.length(rows) > 28 {
    True -> Error(WrongCardinality(logical_target_count, list.length(rows)))
    False -> {
      use _ <- result.try(check_unique(rows, []))
      let actual = list.map(rows, fn(row) { row.id })
      let missing = list.filter(ids(), fn(id) { !list.contains(actual, id) })
      case missing {
        [_, ..] -> Error(MissingTargets(missing))
        [] ->
          case list.length(rows) == logical_target_count {
            False ->
              Error(WrongCardinality(logical_target_count, list.length(rows)))
            True -> list.try_each(rows, validate_target)
          }
      }
    }
  }
}

fn lexical_path(roots: Roots, locator: Locator) -> Result(String, Error) {
  let path = case locator {
    RepositoryRelative(path) -> Ok(roots.repository <> "/" <> path)
    HomeRelative(path) -> Ok(roots.home <> "/" <> path)
    EcologyUnitEnvironmentGroup(UnresolvedEnvironment) ->
      Error(UnknownEnvironment(EcologyComponent))
  }
  use path <- result.try(path)
  case string.byte_size(path) <= 4096 {
    True -> Ok(path)
    False -> Error(MappingTooLong)
  }
}

pub fn roots(repository: String, home: String) -> Result(Roots, Error) {
  case safe_root(repository) && safe_root(home), repository == home {
    False, _ -> Error(InvalidRoot)
    True, True -> Error(AliasedRoots)
    True, False -> {
      let roots = Roots(repository, home)
      let known =
        canonical()
        |> list.filter(fn(row) { row.id != EcologyComponent })
      use paths <- result.try(
        list.try_map(known, fn(row) { lexical_path(roots, row.locator) }),
      )
      case list.length(list.unique(paths)) == list.length(paths) {
        False -> Error(AliasedMapping)
        True -> Ok(roots)
      }
    }
  }
}

/// Pure lexical location only; successful mapping is not an observed file,
/// canonical root identity, symlink check or authorization to write it.
pub fn resolve(roots: Roots, row: Target) -> Result(MappedFile, Error) {
  use _ <- result.try(validate_target(row))
  use absolute <- result.try(lexical_path(roots, row.locator))
  let #(scope, relative) = case row.locator {
    RepositoryRelative(path) -> #(RepositoryRoot, path)
    HomeRelative(path) -> #(HomeRoot, path)
    EcologyUnitEnvironmentGroup(UnresolvedEnvironment) -> #(HomeRoot, "")
  }
  Ok(MappedFile(row.id, row.owner, scope, relative, absolute))
}

pub fn id_label(id: TargetId) -> String {
  case id {
    WorkspaceClaudeMcp -> "workspace_claude_mcp"
    WorkspaceCodexConfig -> "workspace_codex_config"
    WorkspaceAgySettings -> "workspace_agy_settings"
    WorkspacePiMcp -> "workspace_pi_mcp"
    ReleasePointer -> "release_pointer"
    CockpitService -> "cockpit_service"
    EcologyComponent -> "ecology_component"
    HomeAgyAntigravityMcp -> "home_agy_antigravity_mcp"
    HomeAgyConfigMcp -> "home_agy_config_mcp"
    HomeAgySettings -> "home_agy_settings"
    HomeCodexConfig -> "home_codex_config"
    HomeClaudeConfig -> "home_claude_config"
    HomePiMcp -> "home_pi_mcp"
    HomePiMcpAdapter -> "home_pi_mcp_adapter"
  }
}

fn owner_label(owner: Owner) -> String {
  case owner {
    Claude -> "Claude"
    Codex -> "Codex"
    Agy -> "AGY"
    Pi -> "Pi"
    EcologyRuntime -> "EcologyRuntime"
    CockpitRuntime -> "CockpitRuntime"
  }
}

fn locator_json(locator: Locator) -> json.Json {
  case locator {
    RepositoryRelative(path) ->
      json.object([
        #("kind", json.string("repository_relative")),
        #("path", json.string(path)),
      ])
    HomeRelative(path) ->
      json.object([
        #("kind", json.string("home_relative")),
        #("path", json.string(path)),
      ])
    EcologyUnitEnvironmentGroup(UnresolvedEnvironment) ->
      json.object([
        #("kind", json.string("ecology_unit_environment_logical_group")),
        #("unit_name_template", json.string("uos-ecology@CAPSULE.service")),
        #("environment_status", json.string("UNKNOWN")),
        #("environment_locator", json.null()),
        #("resolution", json.string("HOLD_UNRESOLVED_ENVIRONMENT")),
        #(
          "tracked_template_source_hint",
          json.string("ops/web/20260909-0249-uos-ecology@.service"),
        ),
        #(
          "tracked_environment_directive_hint",
          json.string(
            "EnvironmentFile=%h/NAS-setup/uos/var/releases/ecology/%i.env",
          ),
        ),
        #("hint_is_authenticated_live_observation", json.bool(False)),
      ])
  }
}

fn make_json() -> json.Json {
  json.object([
    #("schema", json.string("uos-cutover-logical-targets-v1")),
    #("status", json.string("CATALOG_ONLY_UNVERIFIED")),
    #("authority", json.string("NONE")),
    #("logical_targets", json.int(logical_target_count)),
    #("configuration_targets", json.int(configuration_target_count)),
    #("repository_configurations", json.int(4)),
    #("home_configurations", json.int(7)),
    #("runtime_logical_targets", json.int(runtime_target_count)),
    #("physical_file_count", json.null()),
    #("unresolved_environment_groups", json.int(1)),
    #("filesystem_identity_verified", json.bool(False)),
    #("release_authorized", json.bool(False)),
    #(
      "targets",
      json.array(canonical(), fn(row) {
        json.object([
          #("id", json.string(id_label(row.id))),
          #("owner", json.string(owner_label(row.owner))),
          #("configuration", json.bool(is_configuration(row.id))),
          #("locator", locator_json(row.locator)),
        ])
      }),
    ),
  ])
}

/// Complete inventory validation precedes export; output order is canonical.
pub fn export(rows: List(Target)) -> Result(json.Json, Error) {
  use _ <- result.try(validate_inventory(rows))
  Ok(make_json())
}

pub fn catalog_json() -> json.Json {
  make_json()
}
