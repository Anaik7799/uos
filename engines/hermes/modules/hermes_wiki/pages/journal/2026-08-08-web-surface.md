# Journal: the web surface — wiki, ZK, dashboard, one hub (2026-08-08)

## Prompts (verbatim, in order)

> get the full zigvm harness wiki, web ui and zk functionality into the
> harness completely. create a detailed plan to migrate and create zk and
> wiki for this harness. provide access to wiki, zk and system dasboard on
> a web interface. all system state and key admin and user use cases
> should be connected to 1 site index page. each component , operational
> functionality and usecase and key kpis shoul be accessable via this
> page. provide rich analytics and visual analysis

> execute plan to complete all the gap items. track everting in harness
> plan module

> the webpages must always be acessable via tailscale connectivity, use
> fqdn . this is mandatory requirejment. add a rule
> get zigvm wiki, web ui, ziki skills, rules, claude.md , agent and all
> conig in the harness. get timestamp and journal related rules and config
> from zigvm to harness

> no content is being generated on the webpages. verify the content via
> playwright

## What landed

1. **W0 content migration** — the six Hermes-topic notes from the
   zigvm-era `docs/zk|wiki` trees moved into `docs/hermes/{zk,wiki}` with
   `migrated_from` provenance frontmatter.

2. **`hermes_wiki.ml` (27/0)** — the ZK core ported from the zigvm
   `docs_wiki` model (R14): frontmatter meta (stable id, status, discourse
   type, generated, migrated_from), fence-aware wikilink/tag extraction,
   typed `[[T|@rel]]` edges, backlinks WITH citation context and the
   zigvm domain law `fst back_ctx == backlinks`, a line-machine markdown
   renderer where a missing wikilink is VISIBLY missing. Live finding:
   the real corpus cross-references with ordinary markdown links, so
   relative `.md` links now join the graph as the same relation (external
   URLs never do) — added as two tested laws.

3. **`web_read_model.ml` + `site_build.ml` (33/0)** — the typed
   projection (counts EQUAL their registries; store-absent yields None,
   never a fabricated KPI) and the 91-page site: ONE index hub reaching
   every component (a page each, with algebra/aspects/edges/formal
   backing), every use case, every operational surface with exit codes,
   the KPI band, wiki, ZK graph, atlas, analytics, and the plan. Five
   completeness directions are tested plus a no-dead-links law and
   structural read-only laws (no form, no script, no external host).

4. **`hermes_httpd.ml` (22/0)** — a zero-dependency read-only server
   (Dream is not installed here; R14 says mirror the shape, not the
   library). The route table IS the built page list, so traversal is
   impossible by construction; GET/HEAD only, everything else 405. Tested
   as a pure function plus a LIVE loopback leg.

5. **R15 — Tailscale by FQDN, mandatory.** The server binds all
   interfaces, resolves the MagicDNS name (`.ts.net` suffix required so a
   stray field cannot masquerade), prints it as canonical, and REFUSES to
   start without it (`--allow-no-tailscale` serves degraded, disclosed —
   the R2 discipline). Live: `http://vm-1.tail55d152.ts.net:8790/`.

6. **R16 — journal/ZK timestamp and identity conventions** imported from
   zigvm: `YYYY-MM-DD-<slug>` journals (append-only), `YYYYMMDD-<slug>`
   ZK notes, the frontmatter control panel, and "timestamps are read from
   the environment, never invented".

7. **`gap_plan.ml`** — the tracker the directive asked for: all 55 gap
   items as data, and where a live predicate exists the status is DERIVED
   from the running system, so closing work flips the plan page with no
   edit to a status field. `stale_declarations` reports any disagreement.
   Rendered at `/plan.html`. Phase-0 item F-LX-1 was CLOSED in the same
   pass (the `LX_control` constructor now exists, and the plan's own
   predicate proves it).

8. **R12 registration**: hermes_wiki, web_read_model, site_build,
   hermes_httpd, gap_plan — ontology 33 components / 46 edges, 919/0;
   coverage registry 30/0 with all four aspect dimensions each.

## The Playwright verification (and what it caught)

The Playwright MCP could not launch (it wants Chrome at a root-owned
path; no sudo here), so verification ran through the Chromium that
Playwright itself manages, headless: DOM dumps plus screenshots.

Result: **content was never missing** — the index DOM carries 49 cards,
59 links, the full KPI band; analytics carries three SVG charts. The
likely cause of "no content" was simply that no server was running at the
time (earlier runs were killed after each check); the server now runs
persistently.

But the browser DID catch two real layout defects that markup assertions
could not:
- a long KPI value (the snapshot digest) overflowed its card into the
  neighbouring one;
- the LX level row was wider than its own SVG viewBox and clipped its
  own count.

Both fixed (wrap inside the card; the chart's viewBox is computed from
its widest row) and both pinned as new "rendered-layout laws" in
test_site_build — the class of defect that only a real render exposes now
has tests.

## Numbers

hermes_wiki 27/0 · site_build 33/0 · hermes_httpd 22/0 · ontology 919/0
(33 components, 46 edges) · coverage 30/0 · battery 71 suites / 0
failing · site 91 pages.
