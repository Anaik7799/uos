import cepaf_gleam/ecology/cutover_targets as c
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

pub fn exact_fourteen_logical_inventory_test() {
  let rows = c.canonical()
  list.length(rows) |> should.equal(14)
  c.validate_inventory(rows) |> should.equal(Ok(Nil))
  rows
  |> list.filter(fn(row) { c.is_configuration(row.id) })
  |> list.length
  |> should.equal(11)
  rows
  |> list.filter(fn(row) { !c.is_configuration(row.id) })
  |> list.length
  |> should.equal(3)
  rows
  |> list.filter(fn(row) {
    c.is_configuration(row.id)
    && case row.locator {
      c.RepositoryRelative(_) -> True
      _ -> False
    }
  })
  |> list.length
  |> should.equal(4)
  rows
  |> list.filter(fn(row) {
    c.is_configuration(row.id)
    && case row.locator {
      c.HomeRelative(_) -> True
      _ -> False
    }
  })
  |> list.length
  |> should.equal(7)
}

pub fn independent_handover_owner_and_basename_cases_test() {
  [
    #(c.WorkspaceClaudeMcp, c.Claude, c.RepositoryRelative(".mcp.json")),
    #(
      c.WorkspaceCodexConfig,
      c.Codex,
      c.RepositoryRelative(".codex/config.toml"),
    ),
    #(
      c.WorkspaceAgySettings,
      c.Agy,
      c.RepositoryRelative(".gemini/settings.json"),
    ),
    #(c.WorkspacePiMcp, c.Pi, c.RepositoryRelative(".pi/mcp.json")),
    #(
      c.HomeAgyAntigravityMcp,
      c.Agy,
      c.HomeRelative(".gemini/antigravity-cli/mcp_config.json"),
    ),
    #(
      c.HomeAgyConfigMcp,
      c.Agy,
      c.HomeRelative(".gemini/config/mcp_config.json"),
    ),
    #(c.HomeAgySettings, c.Agy, c.HomeRelative(".gemini/settings.json")),
    #(c.HomeCodexConfig, c.Codex, c.HomeRelative(".codex/config.toml")),
    #(c.HomeClaudeConfig, c.Claude, c.HomeRelative(".claude.json")),
    #(c.HomePiMcp, c.Pi, c.HomeRelative(".pi/agent/mcp.json")),
    #(c.HomePiMcpAdapter, c.Pi, c.HomeRelative(".pi/agent/mcp-adapter.json")),
    #(
      c.ReleasePointer,
      c.EcologyRuntime,
      c.RepositoryRelative("var/releases/ecology/current-mcp-release"),
    ),
    #(
      c.CockpitService,
      c.CockpitRuntime,
      c.HomeRelative(".config/systemd/user/c3i-gleam-server.service"),
    ),
  ]
  |> list.each(fn(expected) {
    let #(id, owner, locator) = expected
    c.target(id) |> should.equal(c.Target(id, owner, locator))
  })
  c.target(c.EcologyComponent)
  |> should.equal(c.Target(
    c.EcologyComponent,
    c.EcologyRuntime,
    c.EcologyUnitEnvironmentGroup(c.UnresolvedEnvironment),
  ))
}

pub fn inventory_missing_duplicate_owner_and_case_refused_test() {
  let rows = c.canonical()
  list.each(rows, fn(row) {
    c.validate_inventory(list.filter(rows, fn(other) { other.id != row.id }))
    |> should.equal(Error(c.MissingTargets([row.id])))
    c.validate_inventory([row, ..rows])
    |> should.equal(Error(c.DuplicateTarget(row.id)))
    let wrong =
      c.Target(..row, owner: case row.owner {
        c.Pi -> c.Claude
        _ -> c.Pi
      })
    c.validate_inventory(
      list.map(rows, fn(other) {
        case other.id == row.id {
          True -> wrong
          False -> other
        }
      }),
    )
    |> should.equal(Error(c.TargetMismatch(row.id)))
  })
  c.validate_inventory(list.repeat(c.target(c.HomePiMcp), 29))
  |> should.equal(Error(c.WrongCardinality(14, 29)))
  let assert Ok(roots) = c.roots("/srv/uos", "/home/operator")
  c.resolve(
    roots,
    c.Target(c.HomePiMcp, c.Pi, c.HomeRelative(".pi/agent/MCP.json")),
  )
  |> should.equal(Error(c.TargetMismatch(c.HomePiMcp)))
}

pub fn pure_root_mapping_and_equal_basename_separation_test() {
  let assert Ok(roots) = c.roots("/home/operator/uos", "/home/operator")
  let assert Ok(repo) = c.resolve(roots, c.target(c.WorkspaceAgySettings))
  let assert Ok(home) = c.resolve(roots, c.target(c.HomeAgySettings))
  repo.absolute |> should.equal("/home/operator/uos/.gemini/settings.json")
  home.absolute |> should.equal("/home/operator/.gemini/settings.json")
  { repo.absolute == home.absolute } |> should.be_false
  c.roots("/tmp/shared", "/tmp/shared") |> should.equal(Error(c.AliasedRoots))
  c.roots("/" <> string.repeat("x", 4089), "/home/operator")
  |> should.equal(Error(c.MappingTooLong))
}

pub fn unsafe_root_and_locator_inputs_fail_closed_test() {
  [
    "", "relative", "~", "/", "/tmp/../home", "/tmp/./home", "//tmp/home",
    "/tmp/home/", "/tmp//home", "/proc", "/proc/1", "/dev/null", "/sys/x",
    "/tmp/.jj", "/tmp/space root", "/tmp/back\\slash", "/tmp/nul\u{0000}path",
  ]
  |> list.each(fn(root) {
    c.roots(root, "/home/operator") |> should.equal(Error(c.InvalidRoot))
    c.roots("/srv/uos", root) |> should.equal(Error(c.InvalidRoot))
  })
  let assert Ok(roots) = c.roots("/srv/uos", "/home/operator")
  [
    "../mcp.json",
    "/etc/passwd",
    ".pi/../mcp.json",
    ".pi//mcp.json",
    "./mcp.json",
    ".jj/config",
    "bad\u{0000}path",
  ]
  |> list.each(fn(relative) {
    c.resolve(
      roots,
      c.Target(c.WorkspacePiMcp, c.Pi, c.RepositoryRelative(relative)),
    )
    |> should.equal(Error(c.UnsafeLocator(c.WorkspacePiMcp)))
  })
}

pub fn runtime_environment_is_unknown_not_a_fourteenth_file_test() {
  let assert Ok(roots) = c.roots("/srv/uos", "/home/operator")
  c.resolve(roots, c.target(c.EcologyComponent))
  |> should.equal(Error(c.UnknownEnvironment(c.EcologyComponent)))
  let mapped =
    c.canonical()
    |> list.filter_map(fn(row) { c.resolve(roots, row) })
  list.length(mapped) |> should.equal(13)
  let text = json.to_string(c.catalog_json())
  let assert Ok(physical) =
    json.parse(
      text,
      decode.at(["physical_file_count"], decode.optional(decode.int)),
    )
  physical |> should.equal(None)
  let assert Ok(groups) =
    json.parse(text, decode.at(["unresolved_environment_groups"], decode.int))
  groups |> should.equal(1)
  let assert Ok(allowed) =
    json.parse(text, decode.at(["release_authorized"], decode.bool))
  allowed |> should.equal(False)
  let assert Ok(targets) =
    json.parse(text, decode.at(["targets"], decode.list(decode.dynamic)))
  let assert Ok(group) =
    list.find(targets, fn(row) {
      decode.run(row, decode.at(["id"], decode.string))
      == Ok("ecology_component")
    })
  decode.run(group, decode.at(["locator", "environment_status"], decode.string))
  |> should.equal(Ok("UNKNOWN"))
  decode.run(
    group,
    decode.at(
      ["locator", "environment_locator"],
      decode.optional(decode.string),
    ),
  )
  |> should.equal(Ok(None))
}

pub fn export_is_inventory_order_independent_test() {
  let assert Ok(forward) = c.export(c.canonical())
  let assert Ok(reverse) = c.export(list.reverse(c.canonical()))
  json.to_string(forward) |> should.equal(json.to_string(reverse))
  let assert Ok(authority) =
    json.parse(json.to_string(forward), decode.at(["authority"], decode.string))
  authority |> should.equal("NONE")
  c.export([]) |> should.be_error
}
