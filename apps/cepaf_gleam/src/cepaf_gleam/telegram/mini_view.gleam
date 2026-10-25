//// Public Mini App shell. Operational data is fetched only after signed authentication.

import cepaf_gleam/telegram/mini_api
import cepaf_gleam/telegram/types
import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

pub const tailnet = "http://nas-1.tail55d152.ts.net:4100"

fn link(path: String, label: String) -> element.Element(msg) {
  h.a([a.href(tailnet <> path)], [h.text(label)])
}

fn checkpoint(id: String, label: String) -> element.Element(msg) {
  h.div([a.class("tg-list-cell"), a.attribute("role", "listitem")], [
    h.label([], [
      h.input([a.type_("checkbox"), a.id(id)]),
      h.text(id <> " — " <> label),
    ]),
  ])
}

fn domain(
  title: String,
  checks: List(#(String, String)),
) -> element.Element(msg) {
  h.details([a.class("tg-card")], [
    h.summary([a.class("tg-list-cell")], [h.text(title)]),
    h.div(
      [a.attribute("role", "list")],
      list.map(checks, fn(c) { checkpoint(c.0, c.1) }),
    ),
  ])
}

pub fn public_page(page: types.MiniAppPage) -> String {
  let pages = mini_api.all_pages()
  h.main(
    [a.id("mini-app"), a.attribute("data-page", types.page_to_path(page))],
    [
      h.header([a.class("tg-card")], [
        h.h1([], [h.text("UOS · " <> types.page_to_label(page))]),
        h.p([], [link("/", "nas-1.tail55d152.ts.net:4100")]),
        h.nav([a.attribute("aria-label", "Breadcrumb")], [
          link("/", "Cockpit"),
          h.text(" / "),
          link("/mini-app", "Telegram"),
          h.text(" / " <> types.page_to_label(page)),
        ]),
      ]),
      h.details([], [
        h.summary([], [h.text("Pages")]),
        h.nav(
          [a.attribute("aria-label", "Mini App pages")],
          list.map(pages, fn(p) {
            h.a(
              [
                a.href(tailnet <> types.page_to_path(p)),
                a.class("tg-list-cell"),
              ],
              [h.text(types.page_to_label(p))],
            )
          }),
        ),
      ]),
      h.section(
        [
          a.class("tg-card"),
          a.attribute("aria-labelledby", "observation-title"),
        ],
        [
          h.h2([a.class("tg-section-title"), a.id("observation-title")], [
            h.text("Current observation"),
          ]),
          h.p(
            [
              a.class("tg-status-sub"),
              a.id("mini-status"),
              a.attribute("role", "status"),
              a.attribute("aria-live", "polite"),
            ],
            [
              h.text(
                "Open this page through the configured Telegram bot to authenticate.",
              ),
            ],
          ),
          h.button(
            [a.id("mini-refresh"), a.type_("button"), a.class("tg-btn")],
            [h.text("Load current data")],
          ),
          case page {
            types.MiniTelemetry ->
              h.div([a.id("mini-control")], [
                h.h3([], [h.text("VM log level")]),
                h.p([], [
                  h.text(
                    "Controls require a separate grant. Current implementation is limited to an owned development VM.",
                  ),
                ]),
                h.label([a.for("mini-control-level")], [h.text("New level")]),
                h.select([a.id("mini-control-level")], [
                  h.option([a.value("debug")], "Debug"),
                  h.option([a.value("info")], "Info"),
                  h.option([a.value("notice")], "Notice"),
                  h.option([a.value("warning")], "Warning"),
                  h.option([a.value("error")], "Error"),
                ]),
                h.button(
                  [
                    a.id("mini-control-apply"),
                    a.type_("button"),
                    a.disabled(True),
                    a.class("tg-btn"),
                  ],
                  [h.text("Set VM log level")],
                ),
                h.button(
                  [
                    a.id("mini-control-receipt"),
                    a.type_("button"),
                    a.disabled(True),
                    a.class("tg-btn"),
                  ],
                  [h.text("Check request receipt")],
                ),
                h.button(
                  [
                    a.id("mini-control-reset"),
                    a.type_("button"),
                    a.disabled(True),
                    a.class("tg-btn"),
                  ],
                  [h.text("Close earlier request")],
                ),
                h.p(
                  [
                    a.id("mini-control-status"),
                    a.attribute("role", "status"),
                    a.attribute("aria-live", "polite"),
                  ],
                  [h.text("Load current data before making a change.")],
                ),
              ])
            types.MiniConversation ->
              h.div([a.id("mini-memory-controls")], [
                h.h3([], [h.text("Retained conversation context")]),
                h.p([], [h.text("Clear and reset both remove retained context for this user and chat. Telegram messages and quota usage stay unchanged. Development controls require a separate grant.")]),
                h.button([a.id("mini-memory-clear"),a.type_("button"),a.disabled(True),a.class("tg-btn")],[h.text("Clear history")]),
                h.button([a.id("mini-memory-reset"),a.type_("button"),a.disabled(True),a.class("tg-btn")],[h.text("Reset context")]),
                h.button([a.id("mini-memory-receipt"),a.type_("button"),a.disabled(True),a.class("tg-btn")],[h.text("Check clear receipt")]),
                h.button([a.id("mini-memory-close"),a.type_("button"),a.disabled(True),a.class("tg-btn")],[h.text("Close earlier request")]),
                h.p([a.id("mini-memory-status"),a.attribute("role","status"),a.attribute("aria-live","polite")],[h.text("Load current data before clearing context.")]),
              ])
            types.MiniZenohBrowser ->
              h.div([a.id("mini-topic-controls")], [
                h.label([a.for("mini-topic")], [h.text("Topic")]),
                h.select([a.id("mini-topic"), a.disabled(True)], [
                  h.option([a.value("")], "Load your allowed topics first"),
                ]),
                h.button(
                  [
                    a.id("mini-live"),
                    a.type_("button"),
                    a.disabled(True),
                    a.class("tg-btn"),
                  ],
                  [h.text("Start live refresh")],
                ),
                h.p([a.id("mini-live-status"), a.attribute("role", "status")], [
                  h.text(
                    "Live refresh polls every two seconds for at most five minutes. It is not a native Zenoh subscription.",
                  ),
                ]),
              ])
            _ -> h.div([], [])
          },
          h.dl([a.id("mini-fields")], []),
          h.noscript([], [
            h.text(
              "JavaScript is required for authenticated data. No operational data is included in this public page.",
            ),
          ]),
        ],
      ),
      h.section([a.class("tg-card")], [
        h.h2([], [h.text("Verification obligations")]),
        h.p([], [
          h.text(
            "These checks are an operator checklist. Selecting a box does not grant admission.",
          ),
        ]),
        domain("1 · Metadata and navigation", [
          #("CHK-01-TIME", "Synchronized clock and timestamp"),
          #("CHK-02-TAIL", "Full Tailnet navigation"),
          #("CHK-03-FRACT", "Fractal layer mapping"),
          #("CHK-04-KM", "Knowledge and evidence links"),
        ]),
        domain("2 · Purity and storage safety", [
          #("CHK-05-MUDA", "Excluded dependencies remain absent"),
          #("CHK-06-GRAPH", "Approved graph implementation boundary"),
          #("CHK-07-DRIVE", "Protected storage interlocks"),
        ]),
        domain("3 · Verification", [
          #("CHK-08-C1C8", "Applicable C1–C8 evidence"),
          #("CHK-09-MATH", "Mathematical gate evidence"),
          #("CHK-10-9MOD", "Applicable testing modes"),
          #("CHK-11-REGR", "Current regression results"),
        ]),
        domain("4 · Control and observability", [
          #("CHK-12-GLEAM", "Observed OTP supervision"),
          #("CHK-13-HERMES", "Bounded evidence analysis"),
          #("CHK-14-ZIGVM", "Deterministic runtime evidence"),
          #("CHK-15-MAX", "Isolated inference where applicable"),
          #("CHK-16-OTEL", "Clock and trace identity"),
        ]),
        domain("5 · Governance and Jujutsu", [
          #("CHK-17-SOV", "Independent candidate review and release authority"),
          #("CHK-18-JJ", "Standalone workspace and exact source identity"),
        ]),
        h.details([], [
          h.summary([], [h.text("6 · Provenance")]),
          h.p([], [
            h.text(
              "EV ceiling 93. EV-94..109 remain NOT_ADMITTED. No new EV identifier.",
            ),
          ]),
        ]),
      ]),
      h.footer([a.class("tg-card")], [
        h.nav([a.attribute("aria-label", "System navigation")], [
          link("/planning", "Planning"),
          h.text(" · "),
          link("/wiki", "Wiki"),
          h.text(" · "),
          link("/zk", "ZK"),
          h.text(" · "),
          link("/files/AGENTS.md", "Policy and source"),
        ]),
        h.p([], [
          h.text(
            "UOS · Authenticated observations are evidence, not release authority.",
          ),
        ]),
      ]),
    ],
  )
  |> element.to_string
}
