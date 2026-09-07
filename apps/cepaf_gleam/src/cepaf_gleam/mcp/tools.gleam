// STAMP: SC-MCP-001, SC-TODO-001, SC-ZMOF-005
// AOR: AOR-MCP-001
// Criticality: Level 2 (HIGH) - MCP Tool Registry
//
// Defines all MCP tools available via stdio, Zenoh, and Wisp transports.
// Planning tools backed by Rust NIF (planning_nif) reading Smriti.db directly.

import cepaf_gleam/mcp/protocol.{type ToolDefinition, ToolDefinition}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

@external(erlang, "c3i_nif", "runtime_loaded")
pub fn nif_runtime_available() -> Bool

/// Historical declarations with no executable runtime binding are retained in
/// the catalog as unavailable, and excluded from operational tools/list.
pub const unavailable_tools = [
  "control_loop", "safety_status", "registry_status", "run_selfcheck",
  "run_gate", "zk_search", "sa_bridge_submit", "vault_status",
  "vault_list_secrets", "vault_policy_get", "vault_audit_tail", "vault_health",
]

/// Tools whose adapters call the c3i_nif module. Compatibility aliases are
/// included even though they are not advertised in tools/list.
pub const nif_tools = [
  "plan_status", "plan_list_pending", "plan_list", "plan_get", "plan_add",
  "plan_update", "plan_search", "system_health", "system_dashboard",
  "system_immune", "system_zenoh", "system_verification", "planning_query",
  "todo_status", "knowledge_search", "verification_run", "dark_cockpit_mode",
  "mesh_topology",
]

pub fn unavailable_reason(name: String) -> Option(String) {
  case list.contains(unavailable_tools, name) {
    True -> Some("no runtime binding")
    False ->
      case list.contains(nif_tools, name) && !nif_runtime_available() {
        True -> Some("C3I NIF runtime is not loaded")
        False -> None
      }
  }
}

pub fn operational_tool_definitions() -> List(ToolDefinition) {
  get_tool_definitions()
  |> list.filter(fn(tool) { unavailable_reason(tool.name) == None })
}

pub fn catalog_json() -> json.Json {
  json.object([
    #("page", json.string("MCP Server")),
    #("status", json.string("runtime_not_probed")),
    #(
      "nif_runtime_status",
      json.string(case nif_runtime_available() {
        True -> "available"
        False -> "unavailable"
      }),
    ),
    #("active_sessions", json.null()),
    #("declared_tool_count", json.int(list.length(get_tool_definitions()))),
    #(
      "advertised_tool_count",
      json.int(list.length(operational_tool_definitions())),
    ),
    #(
      "tools",
      json.array(get_tool_definitions(), fn(tool) {
        json.object([
          #("name", json.string(tool.name)),
          #("description", json.string(tool.description)),
          #(
            "status",
            json.string(case unavailable_reason(tool.name) {
              Some(reason) -> "UNAVAILABLE: " <> reason
              None ->
                "ADAPTER_PRESENT: live execution not verified by this catalog"
            }),
          ),
        ])
      }),
    ),
  ])
}

pub fn get_tool_definitions() -> List(ToolDefinition) {
  [
    // -- Planning tools (NIF-backed, authoritative SQLite) --
    ToolDefinition(
      name: "plan_status",
      description: "Get task count summary from Planning.db (active, pending, completed, blocked, total)",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "plan_list_pending",
      description: "List all non-completed tasks (pending, in_progress, blocked) from Planning.db",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "plan_list",
      description: "List tasks filtered by status (pending|in_progress|completed|blocked|all)",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "status",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string(
                    "Filter: pending, in_progress, completed, blocked, or all",
                  ),
                ),
                #(
                  "enum",
                  json.array(
                    [
                      json.string("pending"),
                      json.string("in_progress"),
                      json.string("completed"),
                      json.string("blocked"),
                      json.string("all"),
                    ],
                    of: fn(x) { x },
                  ),
                ),
              ]),
            ),
          ]),
        ),
        #("required", json.array([json.string("status")], of: fn(x) { x })),
      ]),
    ),
    ToolDefinition(
      name: "plan_get",
      description: "Get a single task by ID from Planning.db",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "id",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Task ID (8-char UUID prefix)")),
              ]),
            ),
          ]),
        ),
        #("required", json.array([json.string("id")], of: fn(x) { x })),
      ]),
    ),
    ToolDefinition(
      name: "plan_add",
      description: "Add a new task to Planning.db with title and priority (P0-P3)",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "title",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Task title/description")),
              ]),
            ),
            #(
              "priority",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Priority: P0, P1, P2, or P3")),
                #(
                  "enum",
                  json.array(
                    [
                      json.string("P0"),
                      json.string("P1"),
                      json.string("P2"),
                      json.string("P3"),
                    ],
                    of: fn(x) { x },
                  ),
                ),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          json.array([json.string("title"), json.string("priority")], of: fn(x) {
            x
          }),
        ),
      ]),
    ),
    ToolDefinition(
      name: "plan_update",
      description: "Update a task's status in Planning.db",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "id",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Task ID")),
              ]),
            ),
            #(
              "status",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string(
                    "New status: pending, in_progress, completed, blocked",
                  ),
                ),
                #(
                  "enum",
                  json.array(
                    [
                      json.string("pending"),
                      json.string("in_progress"),
                      json.string("completed"),
                      json.string("blocked"),
                    ],
                    of: fn(x) { x },
                  ),
                ),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          json.array([json.string("id"), json.string("status")], of: fn(x) { x }),
        ),
      ]),
    ),
    ToolDefinition(
      name: "plan_search",
      description: "Search tasks by title (LIKE match, max 100 results)",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "query",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("Search term to match against task titles"),
                ),
              ]),
            ),
          ]),
        ),
        #("required", json.array([json.string("query")], of: fn(x) { x })),
      ]),
    ),
    // -- System data tools (mesh state) --
    ToolDefinition(
      name: "system_health",
      description: "Get mesh system health: container counts, threat level, OODA phase, dark cockpit mode",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "system_dashboard",
      description: "Get full dashboard data: health %, zenoh status, quorum, last update",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "system_immune",
      description: "Get immune system status: threat level, sentinel active, antibody count",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "system_zenoh",
      description: "Get Zenoh mesh status: connected, router endpoint, topic count",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "system_verification",
      description: "Get verification status: test counts, SIL compliance, last run",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    // -- Knowledge & verification tools --
    ToolDefinition(
      name: "knowledge_search",
      description: "Search the knowledge base for relevant information",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "query",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Search query")),
              ]),
            ),
          ]),
        ),
        #("required", json.array([json.string("query")], of: fn(x) { x })),
      ]),
    ),
    ToolDefinition(
      name: "verification_run",
      description: "Run gleam check and return the result",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "read_file",
      description: "Read content from a file",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "path",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Path to the file")),
              ]),
            ),
          ]),
        ),
        #("required", json.array([json.string("path")], of: fn(x) { x })),
      ]),
    ),
    // -- Domain-specific page tools (per-page MCP access) --
    ToolDefinition(
      name: "podman_containers",
      description: "List all Podman containers with health status, image, and ports",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "metabolic_state",
      description: "Get metabolic subsystem state: CPU load, energy, set-point, PID output",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "ooda_phase",
      description: "Get current OODA phase and cycle latencies across 5 tiers",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "fractal_status",
      description: "Get health status for all 8 fractal layers L0-L7",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "prajna_health",
      description: "Get Prajna cockpit health: dark cockpit mode, biomorphic subsystems, circuit breaker",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "dark_cockpit_mode",
      description: "Get current dark cockpit mode (dark/dim/normal/bright/emergency)",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "integrity_check",
      description: "Run Psi invariant checks: 7 constitutional axioms + hash chain verification",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "evolution_metrics",
      description: "Get evolution metrics: Shannon entropy, CCM, ITQS, fitness score, mutation rate",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "mesh_topology",
      description: "Get Zenoh mesh topology: routers, containers, connectivity graph",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "ooda_decide",
      description: "Run live OODA decision via RETE-UL rule engine: evaluates 7 GRL rules against mesh state, returns decision + reason + 5-tier status",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "kms_catalog",
      description: "Get KMS key catalog: active keys, rotation status, encryption algorithms",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    // ─── Secrets Vault (SC-VAULT-001..025, task 116494073339521648) ───
    // Per ZK [zk-c065c63bc60c618a] MCP-via-Zenoh + [zk-5a9aa96b449baa7b] OODA-MCP-Zenoh
    // Pass-8: vault tools registered for AI-agent discovery via MCP.
    ToolDefinition(
      name: "vault_status",
      description: "Get secrets vault status: sealed/active state, last sync age, per-secret freshness counts (fresh/soft-stale/hard-stale), dashboard color (green/amber/red). Returns same shape as GET /api/v1/secret-status.",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "vault_list_secrets",
      description: "List secret names + metadata (version, fetched_at, ttl_seconds, max_ttl_seconds, sensitivity L0/L3/L7) WITHOUT plaintext values. Safe for AI advisory.",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "vault_policy_get",
      description: "Get policy for a named secret (TTL, MaxTTL, RotationDays, Sensitivity). Per SC-VAULT-013 — operator-tunable policy table.",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "name",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("Secret name (e.g., anthropic_api_key)"),
                ),
              ]),
            ),
          ]),
        ),
        #("required", json.array(["name"], json.string)),
      ]),
    ),
    ToolDefinition(
      name: "vault_audit_tail",
      description: "Read recent audit entries since timestamp (timestamps + operation + caller + result, NOT plaintext). For Cloud Audit reconciliation per SC-VAULT-016.",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "since_ts",
              json.object([
                #("type", json.string("integer")),
                #(
                  "description",
                  json.string("Unix seconds; 0 for full history"),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    ToolDefinition(
      name: "vault_health",
      description: "Composite vault health: SC-VAULT-CRYPTO-001 audit (Tongsuo absent), KEK chain status, audit log gap, sync circuit breaker state, formal-spec last-check timestamp. Maps to RETE-UL vault_integrity domain.",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    // -- ZigVM / Hermes Harness Control Loop & Safety tools --
    ToolDefinition(
      name: "control_loop",
      description: "OODA observe/act over SQLite evidence store",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "phase",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("observe or act")),
              ]),
            ),
            #(
              "content",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Log content for act phase")),
              ]),
            ),
            #(
              "layer",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Target layer (default L2)")),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    ToolDefinition(
      name: "safety_status",
      description: "STAMP/STPA safety census: total UCAs, priority bands, enforced constraints",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "registry_status",
      description: "Formal coverage and module registry status",
      input_schema: json.object([
        #("type", json.string("object")),
        #("properties", json.object([])),
      ]),
    ),
    ToolDefinition(
      name: "run_selfcheck",
      description: "Run harness engine selfcheck battery mode (db|graph|cache|sched|ooda|sweep|mutants)",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "name",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Mode name")),
              ]),
            ),
          ]),
        ),
        #("required", json.array(["name"], json.string)),
      ]),
    ),
    ToolDefinition(
      name: "run_gate",
      description: "Execute deterministic admission gate check",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "name",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("Gate name (e.g., GATE-DETERMINACY)"),
                ),
              ]),
            ),
          ]),
        ),
        #("required", json.array(["name"], json.string)),
      ]),
    ),
    ToolDefinition(
      name: "zk_search",
      description: "Search Zettelkasten knowledge notes by query string",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "query",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Search query")),
              ]),
            ),
          ]),
        ),
        #("required", json.array(["query"], json.string)),
      ]),
    ),
    ToolDefinition(
      name: "sa_bridge_submit",
      description: "Submit task or plan to Sa-Plan bridge",
      input_schema: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "task",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("Task title or payload")),
              ]),
            ),
          ]),
        ),
        #("required", json.array(["task"], json.string)),
      ]),
    ),
  ]
}
