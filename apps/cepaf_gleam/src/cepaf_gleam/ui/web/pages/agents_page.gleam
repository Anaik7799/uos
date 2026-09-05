//// Pass-27 — Phase 3d per-page split: agents_view extracted from
//// domain_views.gleam. SC-FILESIZE-001 / SC-MUDA-001 / SC-GLM-UI-001.

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{type SharedMeshState}
import cepaf_gleam/ui/web/page_helpers.{count_in_json, page_header}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn view(_state: SharedMeshState) -> Element(msg) {
  // Live container health from NIF — containers are the physical agent substrate (SC-TRUTH-001)
  let health_raw = c3i_nif.system_health()
  let container_count = count_in_json(health_raw, "container_count")
  let healthy_count = count_in_json(health_raw, "healthy_count")
  let agent_status = case
    healthy_count == container_count && container_count > 0
  {
    True -> "Healthy"
    False -> "Degraded"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Cybernetic Agents",
      "25-agent biomorphic hierarchy — OODA orchestration",
    ),
    shell.section("A2UI Semantic Zoom [SC-HMI-310]", [
      html.div(
        [
          attribute.class("card-grid"),
          attribute.attribute(
            "style",
            "border-bottom: 1px dashed #4b5263; padding-bottom: 1rem; margin-bottom: 1rem;",
          ),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "display: flex; align-items: center; gap: 1rem;",
              ),
            ],
            [
              element.text("Zoom Level: "),
              html.select(
                [
                  attribute.attribute(
                    "style",
                    "background: #1e222a; color: #abb2bf; border: 1px solid #4b5263; padding: 0.25rem;",
                  ),
                ],
                [
                  html.option(
                    [attribute.value("container")],
                    "Physical Container View (L4)",
                  ),
                  html.option(
                    [attribute.value("actor"), attribute.selected(True)],
                    "Logical BEAM Supervision Tree (L2)",
                  ),
                  html.option(
                    [attribute.value("memory")],
                    "Memory Allocation View (L1)",
                  ),
                ],
              ),
              html.span(
                [
                  attribute.attribute(
                    "style",
                    "color: #56b6c2; font-style: italic; font-size: 0.85rem;",
                  ),
                ],
                [
                  element.text(
                    "↳ Rendering 7 nodes (Miller's Law optimization)",
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ]),
    shell.section("Logical Hierarchy (Zoom: Actor)", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Executive", "Healthy", "1", "EXEC-001 (opus)"),
        shell.status_card(
          "Supervisors",
          "Healthy",
          "4",
          "context/domain/test/quality",
        ),
        shell.status_card("Workers", "Healthy", "20", "compile/test/credo/fix"),
        shell.status_card(
          "Substrate Containers",
          agent_status,
          int.to_string(healthy_count) <> "/" <> int.to_string(container_count),
          "live NIF data",
        ),
      ]),
    ]),
    shell.section("Agent Roles", [
      shell.data_table(["Agent", "Role", "Model", "Layer"], [
        ["EXEC-001", "Orchestrator", "opus", "L5"],
        ["SUP-CONTEXT", "Context supervisor", "sonnet", "L5"],
        ["SUP-DOMAIN", "Domain supervisor", "sonnet", "L5"],
        ["SUP-TEST", "Test supervisor", "sonnet", "L5"],
        ["SUP-QUALITY", "Quality supervisor", "sonnet", "L5"],
        ["WRK-COMPILE", "Compile worker ×5", "haiku", "L4"],
        ["WRK-TEST", "Test worker ×5", "haiku", "L4"],
        ["WRK-CREDO", "Credo worker ×5", "haiku", "L4"],
        ["WRK-FIX", "Fix worker ×5", "haiku", "L4"],
      ]),
    ]),
    shell.section("L2 Operational Controls [A2UI Agentic Interface]", [
      html.div([attribute.class("card-grid")], [
        shell.apalache_guard(
          shell.action_button(
            "Start/Stop/Restart Actor",
            "/api/v1/podman/action",
            "{\\\"verb\\\": \\\"restart_actor\\\", \\\"container\\\": \\\"all\\\", \\\"reason\\\": \\\"Actor refresh\\\"}",
          ),
          "mathematically_safe",
        ),
        shell.apalache_guard(
          shell.action_button(
            "Compile",
            "/api/v1/podman/action",
            "{\\\"verb\\\": \\\"compile\\\", \\\"container\\\": \\\"all\\\", \\\"reason\\\": \\\"Build\\\"}",
          ),
          "mathematically_safe",
        ),
        shell.apalache_guard(
          shell.action_button(
            "Test SIL-6",
            "/api/v1/podman/action",
            "{\\\"verb\\\": \\\"test\\\", \\\"container\\\": \\\"all\\\", \\\"reason\\\": \\\"Verify\\\"}",
          ),
          "mathematically_safe",
        ),
      ]),
    ]),
    shell.section("DB3 — OODA Cycle Trace", [shell.ooda_trace_viewer()]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/agents-grid.bundled.js?v=pass45")],
      [],
    ),
  ])
}
