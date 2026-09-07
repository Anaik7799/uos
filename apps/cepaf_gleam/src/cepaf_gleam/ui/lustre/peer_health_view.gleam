//// N01 diagnostic rendering. This view receives the same typed report as JSON
//// and TUI consumers, and cannot convert reachability into verification.

import cepaf_gleam/verification/peer_health
import lustre/attribute
import lustre/element.{type Element, text}
import lustre/element/html

pub fn view(report: peer_health.Report) -> Element(message) {
  html.section(
    [
      attribute.id("peer-health"),
      attribute.attribute("aria-labelledby", "peer-health-title"),
      attribute.attribute("data-peer-state", peer_health.state_name(report)),
    ],
    [
      html.h1([attribute.id("peer-health-title")], [
        text("VM-1 peer diagnostic"),
      ]),
      html.p([attribute.attribute("role", "status")], [
        text(peer_health.summary(report)),
      ]),
      html.p([], [
        text(
          "The earlier port 8088 link is obsolete. The C3I HTTP listener is configured on port 4100.",
        ),
      ]),
      html.p([], [
        html.a([attribute.href(peer_health.current_url)], [
          text(peer_health.current_url),
        ]),
      ]),
      html.p([], [
        text(
          "A responding service does not establish a verified build or healthy actor communication. This report grants no system admission.",
        ),
      ]),
      html.p([], [
        html.a(
          [
            attribute.href(
              "http://nas-1.tail55d152.ts.net:4100/api/peer/health",
            ),
          ],
          [text("Read the current diagnostic as JSON")],
        ),
      ]),
      html.p([], [
        html.a([attribute.href("http://nas-1.tail55d152.ts.net:4100/peer")], [
          text("Run the bounded read-only diagnostic again"),
        ]),
      ]),
    ],
  )
}
