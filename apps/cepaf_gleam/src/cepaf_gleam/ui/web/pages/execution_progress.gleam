import cepaf_gleam/planning/execution_observer as observer
import cepaf_gleam/planning/execution_projection as execution
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

const base = "http://nas-1.tail55d152.ts.net:4100"

fn link(path: String, title: String) -> Element(msg) {
  html.a([attribute.href(base <> path)], [html.text(title)])
}

fn metric(label: String, count: Int) -> Element(msg) {
  html.div([attribute.class("rounded border border-slate-700 p-4")], [
    html.div([attribute.class("text-2xl font-bold")], [
      html.text(int.to_string(count)),
    ]),
    html.div([], [html.text(label)]),
  ])
}

fn cell(text: String) -> Element(msg) {
  html.td([attribute.class("p-3 align-top")], [html.text(text)])
}

fn task_row(
  row: execution.Row,
  priorities: Dict(String, execution.Risk),
) -> Element(msg) {
  html.tr([attribute.class("border-t border-slate-700")], [
    html.td([attribute.class("p-3 align-top")], [
      html.strong([], [html.text(row.task.id)]),
      html.p([], [html.text(row.task.title)]),
    ]),
    cell(
      execution.status_label(row.status) <> " (DB: " <> row.task.state <> ")",
    ),
    cell(
      case row.task.worker {
        None -> "Unassigned"
        Some(worker) -> worker
      }
      <> " / attempt "
      <> int.to_string(row.task.attempt),
    ),
    cell(
      case row.risk {
        None -> "Unknown"
        Some(risk) ->
          risk.class
          <> " / "
          <> int.to_string(execution.score(risk))
          <> " (declared)"
      }
      <> case dict.get(priorities, row.task.id) {
        Error(_) -> ""
        Ok(risk) ->
          "; effective "
          <> risk.class
          <> " / "
          <> int.to_string(execution.score(risk))
          <> " from "
          <> risk.task_id
      },
    ),
    cell(case row.task.dependencies {
      [] -> "None"
      dependencies -> string.join(dependencies, ", ")
    }),
    cell(string.join(row.reasons, "; ")),
  ])
}

pub fn render(outcome: Result(observer.Observation, String)) -> Element(msg) {
  html.section(
    [
      attribute.id("canonical-execution-progress"),
      attribute.class("p-6 space-y-6"),
    ],
    [
      html.h1([], [html.text("Sa-plan execution progress")]),
      html.p([], [html.text("Canonical plan: " <> execution.plan_id)]),
      html.nav([attribute.attribute("aria-label", "Execution navigation")], [
        link("/planning", "Refresh current observation"),
        html.text(" · "),
        link("/api/planning/tasks", "JSON progress"),
        html.text(" · "),
        link(
          "/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md",
          "Recovery and optimization plan",
        ),
      ]),
      html.p([attribute.attribute("role", "note")], [
        html.text(
          "Read-only observation. Sa-plan owns all execution. Task completion is not system admission; no claim, retry or deployment is performed here.",
        ),
      ]),
      case outcome {
        Error(reason) ->
          html.div(
            [
              attribute.attribute("role", "alert"),
              attribute.class("rounded border border-red-500 p-4"),
            ],
            [
              html.h2([], [html.text("Task progress unavailable")]),
              html.p([], [html.text(reason)]),
              html.p([], [
                html.text(
                  "No completion percentage or ready queue can be inferred from unavailable data.",
                ),
              ]),
            ],
          )
        Ok(observation) -> {
          let snapshot = observation.snapshot
          html.div([attribute.class("space-y-6")], [
            html.p([], [html.text("Observed UTC: " <> snapshot.observed_at)]),
            html.h2([], [
              html.text(
                int.to_string(snapshot.completed)
                <> " / "
                <> int.to_string(snapshot.total)
                <> " canonical tasks completed",
              ),
            ]),
            element.element(
              "progress",
              [
                attribute.attribute("value", int.to_string(snapshot.completed)),
                attribute.attribute("max", int.to_string(snapshot.total)),
                attribute.attribute("aria-label", "Canonical task completion"),
              ],
              [
                html.text(
                  int.to_string(snapshot.completed)
                  <> " / "
                  <> int.to_string(snapshot.total),
                ),
              ],
            ),
            html.div(
              [attribute.class("grid grid-cols-2 lg:grid-cols-5 gap-3")],
              [
                metric("Completed with receipt", snapshot.completed),
                metric("Executing with current lease", snapshot.executing),
                metric("Blocked", snapshot.blocked),
                metric("Unknown / needs reconciliation", snapshot.unknown),
                metric(
                  "Candidates for preflight only",
                  list.length(snapshot.recommendations),
                ),
              ],
            ),
            html.h2([], [html.text("Execution optimization")]),
            html.p([], [
              html.text(
                "Authority and dependency readiness first, then safety class and criticality × STPA × FMEA × dependency × impact. Consumer urgency propagates to prerequisites without making blocked tasks eligible. Ties use oldest ready time and stable task ID. Cost/effort evidence is unavailable; no global optimum is asserted.",
              ),
            ]),
            html.p([], [
              html.text(
                "Recommended preflight order: "
                <> case snapshot.recommendations {
                  [] -> "None. Resolve visible blockers or refresh evidence."
                  ids -> string.join(ids, " → ")
                },
              ),
            ]),
            html.p([], [
              html.text(
                "Risk scores are declarations, not source-verified dispatch authorization. Unknown or expired evidence never becomes ready. Re-run source-bound risk preflight, then claim through Sa-plan and check effect-time fences.",
              ),
            ]),
            html.div(
              [
                attribute.class("overflow-x-auto"),
                attribute.attribute("tabindex", "0"),
                attribute.attribute("role", "region"),
                attribute.attribute("aria-label", "Canonical task table"),
              ],
              [
                html.table([attribute.class("w-full text-left")], [
                  html.caption([], [
                    html.text(
                      "All tasks in this plan, including unfinished work",
                    ),
                  ]),
                  html.thead([], [
                    html.tr(
                      [],
                      list.map(
                        [
                          "Task",
                          "Progress",
                          "Owner / attempt",
                          "Risk / score",
                          "Dependencies",
                          "Why / next action",
                        ],
                        fn(title) {
                          html.th(
                            [
                              attribute.attribute("scope", "col"),
                              attribute.class("p-3"),
                            ],
                            [html.text(title)],
                          )
                        },
                      ),
                    ),
                  ]),
                  html.tbody(
                    [],
                    list.map(snapshot.rows, fn(row) {
                      task_row(row, snapshot.priorities)
                    }),
                  ),
                ]),
              ],
            ),
            html.details([], [
              html.summary([], [
                html.text("Observation provenance and limitations"),
              ]),
              html.p([], [html.text("Database: " <> observer.database)]),
              html.p([], [
                html.text("Task snapshot SHA-256: " <> observation.task_sha256),
              ]),
              html.p([], [
                html.text("Risk snapshot SHA-256: " <> observation.risk_sha256),
              ]),
              link("/files/" <> observer.risk_path, "Risk portfolio"),
              html.p([], [
                html.text(
                  "One read-only SQLite SELECT; risk file and clock are separate bounded observations. Reload to refresh. Full MCP coverage, hive usability and production admission remain separate acceptance gates.",
                ),
              ]),
            ]),
          ])
        }
      },
      checklist(),
      html.footer([], [
        html.text(
          "UOS · #fractal-l0–l9 · #zero-muda · development observation, not admission. ",
        ),
        link("/", "Previous: cockpit"),
        html.text(" · "),
        link("/checklist", "Next: verification checklist"),
      ]),
    ],
  )
}

fn checklist() -> Element(msg) {
  let domains = [
    #("Metadata and navigation", [
      #("CHK-01-TIME", "Observe synchronized clock and evidence freshness"),
      #("CHK-02-TAIL", "Verify Tailnet delivery and navigation"),
      #("CHK-03-FRACT", "Account for L0–L9 applicability"),
      #("CHK-04-KM", "Reconcile knowledge and artifact sources"),
    ]),
    #("Purity and storage safety", [
      #("CHK-05-MUDA", "Verify excluded dependency boundaries"),
      #("CHK-06-GRAPH", "Verify language and bounded native boundaries"),
      #("CHK-07-DRIVE", "Preserve OS-storage interlock and data"),
    ]),
    #("Testing and mathematical gates", [
      #("CHK-08-C1C8", "Exercise all applicable client surfaces"),
      #("CHK-09-MATH", "Bind mathematical gates to candidate"),
      #("CHK-10-9MOD", "Record applicable test modalities"),
      #("CHK-11-REGR", "Observe fresh regressions and failures"),
    ]),
    #("Control and observability", [
      #("CHK-12-GLEAM", "Verify actual OTP supervision and fences"),
      #("CHK-13-HERMES", "Verify bounded formal/evidence services"),
      #("CHK-14-ZIGVM", "Verify deterministic kernel and VFS"),
      #("CHK-15-MAX", "Verify isolated inference where applicable"),
      #("CHK-16-OTEL", "Correlate actual control and data traces"),
    ]),
    #("Governance and standalone Jujutsu", [
      #("CHK-17-SOV", "Obtain independent review and admission"),
      #("CHK-18-JJ", "Bind standalone JJ candidate and ownership"),
    ]),
  ]
  html.section([attribute.id("execution-verification-checklist")], [
    html.h2([], [html.text("Comprehensive verification checklist")]),
    html.p([], [
      html.text(
        "18 obligations, not 18 passing claims. Consult the task's candidate-bound evidence; runtime and formal checks not observed here remain UNRUN.",
      ),
    ]),
    html.div(
      [],
      list.map(domains, fn(domain) {
        html.details([], [
          html.summary([], [html.text(domain.0)]),
          html.ul(
            [],
            list.map(domain.1, fn(check) {
              html.li([], [
                html.text(check.0 <> " — " <> check.1 <> ": evidence required"),
              ])
            }),
          ),
        ])
      }),
    ),
    html.details([], [
      html.summary([], [html.text("Provenance extension")]),
      html.p([], [
        html.text(
          "Admitted EV ceiling 93. EV-94..109 NOT_ADMITTED; no new EV is minted. Task results and advisory scores cannot grant admission.",
        ),
      ]),
    ]),
  ])
}
