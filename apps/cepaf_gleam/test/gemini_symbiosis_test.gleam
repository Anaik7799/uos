/// Gemini CLI Symbiosis and Parity Test Suite
/// 
/// This suite verifies the exhaustive functional parity between the legacy .claude
/// and the new .gemini integration, ensuring no regressions during migration.
/// It also checks for the activation of new Gemini-specific symbiosis features.
///
/// STAMP: SC-GEM-001..007, SC-ZETTEL-004
/// Layer: L5_COGNITIVE
import cepaf_gleam/substrate/file_system
import gleam/list
import gleam/string
import gleeunit/should

fn get_root() -> String {
  case file_system.run_cmd("git rev-parse --show-toplevel") {
    Ok(root) -> string.trim(root)
    Error(_) -> "."
  }
}

fn list_files(dir: String) -> List(String) {
  let path = get_root() <> "/" <> dir
  case file_system.run_cmd("ls -1 " <> path <> " 2>/dev/null") {
    Ok(output) -> {
      output
      |> string.split("\n")
      |> list.filter(fn(s) { string.trim(s) != "" })
    }
    Error(_) -> []
  }
}

// =============================================================================
// 1.0 — Directory Structure Parity
// =============================================================================

pub fn gemini_root_directory_exists_test() {
  let root = get_root()
  file_system.run_cmd("test -d " <> root <> "/.gemini")
  |> should.be_ok()
}

pub fn gemini_subdirectories_exist_test() {
  let root = get_root()
  let sub_dirs = ["rules", "agents", "skills", "commands", "plans", "worktrees"]
  list.each(sub_dirs, fn(dir) {
    file_system.run_cmd("test -d " <> root <> "/.gemini/" <> dir)
    |> should.be_ok()
  })
}

// =============================================================================
// 1.1 — File Count and Content Parity
// =============================================================================

pub fn rules_parity_test() {
  let claude_rules = list_files(".claude/rules")
  let gemini_rules = list_files(".gemini/rules")

  list.each(claude_rules, fn(rule) {
    let target = string.replace(rule, "claude", "gemini")
    { list.contains(gemini_rules, rule) || list.contains(gemini_rules, target) }
    |> should.be_true()
  })
}

pub fn agents_parity_test() {
  let claude_agents = list_files(".claude/agents")
  let gemini_agents = list_files(".gemini/agents")

  list.each(claude_agents, fn(agent) {
    list.contains(gemini_agents, agent)
    |> should.be_true()
  })
}

pub fn skills_parity_test() {
  let claude_skills = list_files(".claude/skills")
  let gemini_skills = list_files(".gemini/skills")

  list.each(claude_skills, fn(skill) {
    list.contains(gemini_skills, skill)
    |> should.be_true()
  })
}

pub fn commands_parity_test() {
  let claude_commands = list_files(".claude/commands")
  let gemini_commands = list_files(".gemini/commands")

  list.each(claude_commands, fn(cmd) {
    list.contains(gemini_commands, cmd)
    |> should.be_true()
  })
}

pub fn content_reference_migration_test() {
  let root = get_root()
  let gemini_rules = list_files(".gemini/rules")
  list.each(gemini_rules, fn(rule) {
    case file_system.read_file(root <> "/.gemini/rules/" <> rule) {
      Ok(content) -> {
        // Should NOT contain legacy references
        string.contains(content, "CLAUDE.md") |> should.be_false()
      }
      Error(_) -> Nil
    }
  })
}

// =============================================================================
// 1.2 — Configuration Validity
// =============================================================================

pub fn settings_json_exists_test() {
  let root = get_root()
  file_system.run_cmd("test -f " <> root <> "/.gemini/settings.json")
  |> should.be_ok()
}

pub fn settings_local_json_exists_test() {
  let root = get_root()
  file_system.run_cmd("test -f " <> root <> "/.gemini/settings.local.json")
  |> should.be_ok()
}

pub fn mcp_json_exists_test() {
  let root = get_root()
  file_system.run_cmd("test -f " <> root <> "/.mcp.json")
  |> should.be_ok()
}

// =============================================================================
// 2.0 — Symbiosis Feature Checks
// =============================================================================

pub fn gemini_spec_defines_symbiosis_test() {
  let root = get_root()
  case file_system.read_file(root <> "/GEMINI.md") {
    Ok(content) -> {
      string.contains(content, "Cybernetic Architect") |> should.be_true()
      string.contains(content, "save_memory") |> should.be_true()
      string.contains(content, "activate_skill") |> should.be_true()
      string.contains(content, "codebase_investigator") |> should.be_true()
      string.contains(content, "firecrawl") |> should.be_true()
    }
    Error(e) ->
      panic as { "GEMINI.md missing at " <> root <> "/GEMINI.md, error: " <> e }
  }
}

pub fn multilayer_swarm_skill_exists_test() {
  let root = get_root()
  file_system.run_cmd(
    "test -f " <> root <> "/.gemini/skills/multilayer-swarm/SKILL.md",
  )
  |> should.be_ok()
}

pub fn system_engineering_sop_skill_exists_test() {
  let root = get_root()
  file_system.run_cmd(
    "test -f " <> root <> "/.gemini/skills/system-engineering-sop/SKILL.md",
  )
  |> should.be_ok()
}

pub fn gemini_symbiosis_recommendations_test() {
  let root = get_root()
  case file_system.read_file(root <> "/GEMINI.md") {
    Ok(content) -> {
      string.contains(content, "@skill") |> should.be_true()
      string.contains(content, "Jidoka-Triggered Mapping") |> should.be_true()
    }
    Error(_) -> panic as "GEMINI.md missing"
  }
}
