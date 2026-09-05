//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/access_control</module>
////     <fsharp-lineage>Cepaf.Core.AccessControl.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>Access Control, Policy Enforcement, Shell Validation</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-ORCH-013, SC-ACCESS-001 to SC-ACCESS-014</stamp-controls>
////     <aor-rules>AOR-ACCESS-001 to AOR-ACCESS-010</aor-rules>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# AccessPolicy ≅ Gleam AccessPolicy(rules, default_deny)
////     </morphism>
////     <morphism type="injective" loss="fsharp-active-patterns">
////       F# `validateShellCommand` ↪ Gleam `validate_shell_command`
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/planning/graph_verification.{
  type Graph, Edge, Graph, Node, new_graph,
}
import gleam/json
import gleam/list
import gleam/string

// =============================================================================
// Type Definitions
// =============================================================================

/// A single access rule matching an agent pattern to a resource pattern.
pub type AccessRule {
  AccessRule(agent_pattern: String, resource_pattern: String, allowed: Bool)
}

/// An access policy consisting of ordered rules and a default deny flag.
pub type AccessPolicy {
  AccessPolicy(rules: List(AccessRule), default_deny: Bool)
}

/// Result of shell command validation.
pub type ShellCommandValidation {
  Allowed
  Blocked(reason: String)
  RequiresReview(reason: String)
}

// =============================================================================
// Policy Construction
// =============================================================================

/// Create a new access policy with default deny.
pub fn new_policy() -> AccessPolicy {
  AccessPolicy(rules: [], default_deny: True)
}

/// Add a rule to the policy. Rules are evaluated in order (first match wins).
pub fn add_rule(policy: AccessPolicy, rule: AccessRule) -> AccessPolicy {
  AccessPolicy(..policy, rules: list.append(policy.rules, [rule]))
}

// =============================================================================
// Access Checking
// =============================================================================

/// Check if an agent has access to a resource.
/// Evaluates rules in order; first matching rule wins.
/// Falls back to default_deny if no rules match.
pub fn check_access(
  policy: AccessPolicy,
  agent: String,
  resource: String,
) -> Bool {
  let matching_rule =
    list.find(policy.rules, fn(rule) {
      pattern_matches(rule.agent_pattern, agent)
      && pattern_matches(rule.resource_pattern, resource)
    })
  case matching_rule {
    Ok(rule) -> rule.allowed
    Error(_) -> !policy.default_deny
  }
}

/// Simple pattern matching supporting "*" as wildcard for all,
/// and prefix matching with trailing "*".
fn pattern_matches(pattern: String, value: String) -> Bool {
  case pattern {
    "*" -> True
    _ -> {
      case string.ends_with(pattern, "*") {
        True -> {
          let prefix = string.drop_end(pattern, 1)
          string.starts_with(value, prefix)
        }
        False -> pattern == value
      }
    }
  }
}

// =============================================================================
// Shell Command Validation
// =============================================================================

/// Dangerous commands that should always be blocked.
const dangerous_commands = [
  "rm -rf", "rm -fr", "dd if=", "mkfs", "fdisk", "format", ":(){:|:&};:",
  "chmod 777", "chmod -R 777", "> /dev/sda", "wget", "curl | sh", "curl | bash",
  "shutdown", "reboot", "halt", "init 0", "init 6", "kill -9", "killall",
  "pkill -9",
]

/// Commands that require human review for AI agents.
const review_commands = [
  "docker", "podman", "systemctl", "service", "iptables", "ufw", "firewall-cmd",
  "mount", "umount", "chown", "chmod", "apt", "dnf", "yum", "pacman", "nix",
  "pip install", "npm install", "cargo install", "git push", "git rebase",
  "git reset",
]

/// AI agent type identifiers.
const ai_agent_types = [
  "claude", "gpt", "gemini", "copilot", "codex", "anthropic", "openai",
  "google-ai", "meta-ai", "ai-agent", "llm", "assistant",
]

/// Validate a shell command based on the agent type.
/// AI agents face stricter validation than human operators.
pub fn validate_shell_command(
  command: String,
  agent_type: String,
) -> ShellCommandValidation {
  let cmd_lower = string.lowercase(command)
  case is_dangerous_command(cmd_lower) {
    True ->
      Blocked(
        reason: "Dangerous command detected: "
        <> command
        <> " — blocked per SC-ORCH-013",
      )
    False -> {
      case is_ai_agent(agent_type) {
        True -> validate_ai_command(cmd_lower, command)
        False -> Allowed
      }
    }
  }
}

fn validate_ai_command(
  cmd_lower: String,
  original: String,
) -> ShellCommandValidation {
  let needs_review =
    list.any(review_commands, fn(rc) {
      string.contains(cmd_lower, string.lowercase(rc))
    })
  case needs_review {
    True ->
      RequiresReview(
        reason: "AI agent command requires human review: " <> original,
      )
    False -> Allowed
  }
}

/// Check if a command string contains dangerous patterns.
pub fn is_dangerous_command(command: String) -> Bool {
  let cmd_lower = string.lowercase(command)
  list.any(dangerous_commands, fn(dc) { string.contains(cmd_lower, dc) })
}

/// Check if an agent type string represents an AI agent.
pub fn is_ai_agent(agent_type: String) -> Bool {
  let agent_lower = string.lowercase(agent_type)
  list.any(ai_agent_types, fn(ai_type) { string.contains(agent_lower, ai_type) })
}

// =============================================================================
// Graph Integration
// =============================================================================

/// Build an access control graph from a policy, agents, and resources.
/// Nodes are agents and resources; edges represent access relationships.
pub fn build_access_graph(
  policy: AccessPolicy,
  agents: List(String),
  resources: List(String),
) -> Graph {
  let graph = new_graph()
  // Add agent nodes
  let graph =
    list.fold(agents, graph, fn(g, agent) {
      graph_verification.add_node(
        g,
        Node(id: agent, label: agent, node_type: "agent"),
      )
    })
  // Add resource nodes
  let graph =
    list.fold(resources, graph, fn(g, resource) {
      graph_verification.add_node(
        g,
        Node(id: resource, label: resource, node_type: "resource"),
      )
    })
  // Add edges based on policy evaluation
  list.fold(agents, graph, fn(g, agent) {
    list.fold(resources, g, fn(g2, resource) {
      let allowed = check_access(policy, agent, resource)
      let label = case allowed {
        True -> "allowed"
        False -> "denied"
      }
      graph_verification.add_edge(
        g2,
        Edge(from: agent, to: resource, label: label, is_allowed: allowed),
      )
    })
  })
}

/// Verify that no forbidden access paths exist in the graph.
/// A forbidden pattern is a node ID that should have no incoming allowed edges.
pub fn verify_no_forbidden_path(
  graph: Graph,
  forbidden_patterns: List(String),
) -> Bool {
  let Graph(edges: edges, ..) = graph
  let forbidden_edges =
    list.filter(edges, fn(e) {
      e.is_allowed
      && list.any(forbidden_patterns, fn(fp) {
        string.contains(e.to, fp) || string.contains(e.from, fp)
      })
    })
  list.is_empty(forbidden_edges)
}

// =============================================================================
// Policy Queries
// =============================================================================

/// Get all rules that apply to a specific agent.
pub fn get_agent_permissions(
  policy: AccessPolicy,
  agent: String,
) -> List(AccessRule) {
  list.filter(policy.rules, fn(rule) {
    pattern_matches(rule.agent_pattern, agent)
  })
}

/// Get all agents that are explicitly blocked by any rule.
pub fn get_blocked_agents(policy: AccessPolicy) -> List(String) {
  list.filter_map(policy.rules, fn(rule) {
    case rule.allowed {
      False -> Ok(rule.agent_pattern)
      True -> Error(Nil)
    }
  })
  |> list.unique()
}

/// Omega-0 check: Verify that the founder (human:*) has full access to all resources.
pub fn founder_has_full_access(policy: AccessPolicy) -> Bool {
  let founder_rules = get_agent_permissions(policy, "human:founder")
  case list.is_empty(founder_rules) {
    // No explicit rules for founder - check if default allows
    True -> !policy.default_deny
    False -> {
      // Check that all founder rules are allowed and at least one is wildcard
      let all_allowed = list.all(founder_rules, fn(r) { r.allowed })
      let has_wildcard =
        list.any(founder_rules, fn(r) { r.resource_pattern == "*" })
      all_allowed && has_wildcard
    }
  }
}

/// SC-ORCH-013: Deny AI agents direct access to critical resources.
/// Adds deny rules for all known AI agent types to the critical resource pattern.
pub fn deny_ai_direct_access(policy: AccessPolicy) -> AccessPolicy {
  let deny_rules =
    list.map(ai_agent_types, fn(ai_type) {
      AccessRule(
        agent_pattern: ai_type <> "*",
        resource_pattern: "*",
        allowed: False,
      )
    })
  // Prepend deny rules so they take priority (first-match wins)
  AccessPolicy(..policy, rules: list.append(deny_rules, policy.rules))
}

// =============================================================================
// Serialization
// =============================================================================

/// Serialize an access policy to JSON.
pub fn policy_to_json(policy: AccessPolicy) -> json.Json {
  json.object([
    #("rules", json.array(policy.rules, rule_to_json)),
    #("default_deny", json.bool(policy.default_deny)),
    #("rule_count", json.int(list.length(policy.rules))),
  ])
}

fn rule_to_json(rule: AccessRule) -> json.Json {
  json.object([
    #("agent_pattern", json.string(rule.agent_pattern)),
    #("resource_pattern", json.string(rule.resource_pattern)),
    #("allowed", json.bool(rule.allowed)),
  ])
}

/// Serialize a shell command validation result to JSON.
pub fn validation_to_json(result: ShellCommandValidation) -> json.Json {
  case result {
    Allowed ->
      json.object([
        #("status", json.string("allowed")),
        #("reason", json.string("")),
      ])
    Blocked(reason) ->
      json.object([
        #("status", json.string("blocked")),
        #("reason", json.string(reason)),
      ])
    RequiresReview(reason) ->
      json.object([
        #("status", json.string("requires_review")),
        #("reason", json.string(reason)),
      ])
  }
}
