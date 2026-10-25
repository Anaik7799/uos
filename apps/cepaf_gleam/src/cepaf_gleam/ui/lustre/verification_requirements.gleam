//// Canonical requirement display; no receipt means no passing claim.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub const domains = [
  #(
    "Metadata, time and navigation",
    [
      "01 Time and freshness",
      "02 Tailscale navigation",
      "03 Fractal tags",
      "04 Knowledge links",
    ],
  ),
  #(
    "Purity and storage safety",
    ["05 Zero-Muda scope", "06 Native boundaries", "07 Storage interlock"],
  ),
  #(
    "Tests and mathematics",
    [
      "08 C1-C8 coverage",
      "09 Mathematical gates",
      "10 Test modalities",
      "11 Interface regression",
    ],
  ),
  #(
    "Control and observability",
    [
      "12 OTP runtime",
      "13 Hermes contracts",
      "14 ZigVM execution",
      "15 Inference isolation",
      "16 Telemetry correlation",
    ],
  ),
  #(
    "Governance and Jujutsu",
    ["17 Independent verification", "18 Candidate identity"],
  ),
]

pub fn view() -> Element(msg) {
  html.details(
    [
      attribute.class("uos-verification-checklist"),
      attribute.attribute(
        "style",
        "margin:1rem;padding:1rem;border:1px solid #34435b;border-radius:8px;overflow-wrap:anywhere",
      ),
    ],
    [
      html.summary([], [
        html.text(
          "Comprehensive verification checklist: 18 requirements; evidence required",
        ),
      ]),
      html.p([], [
        html.text(
          "No candidate-bound receipts are attached to this view. UNRUN is not PASS.",
        ),
      ]),
      html.details([], [
        html.summary([], [html.text("Provenance")]),
        html.p([], [
          html.text(
            "EV ceiling93; EV94..109 NOT_ADMITTED. Preserved historical claims do not establish current admission.",
          ),
        ]),
      ]),
      ..list.map(domains, fn(domain) {
        html.details([], [
          html.summary([], [html.text(domain.0)]),
          html.ul(
            [],
            list.map(domain.1, fn(label) {
              html.li([], [html.text("UNRUN: " <> label)])
            }),
          ),
        ])
      })
    ],
  )
}
