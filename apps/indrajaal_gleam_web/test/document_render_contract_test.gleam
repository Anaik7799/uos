import gleam/io
import gleam/string
import gleeunit/should
import indrajaal_gleam_web as web

pub fn document_client_parser_has_escaped_newline_test() {
  let page =
    web.render_document_view(
      "Fixture",
      "docs/fixture.md",
      "# Heading\n\nBody",
      "docs",
    )
  // The emitted JavaScript must contain a backslash-n escape inside its quote.
  string.contains(page, "processed.split('\\n')") |> should.be_true
}

pub fn document_source_is_inert_before_rendering_test() {
  let page =
    web.render_document_view(
      "Fixture",
      "docs/fixture.md",
      "</pre><script>bad()</script>",
      "docs",
    )
  string.contains(page, "&lt;/pre&gt;&lt;script&gt;bad()&lt;/script&gt;")
  |> should.be_true
  string.contains(page, "</pre><script>bad()</script>") |> should.be_false
}

pub fn document_checklist_starts_collapsed_test() {
  let page =
    web.render_document_view("Fixture", "docs/fixture.md", "# Heading", "docs")
  string.contains(page, "<details class='checklist-card'>") |> should.be_true
}

pub fn main() {
  io.print(web.render_document_view(
    "Candidate document",
    "docs/fixture.md",
    "# Candidate document\n\nNavigation and source toggle fixture.\n\n[Wiki](http://nas-1.tail55d152.ts.net:4100/wiki)\n\n```gleam\npub fn identity(x) { x }\n```",
    "docs",
  ))
}
