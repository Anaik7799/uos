---
id: hermes-zk-tailscale-web-surface
status: published
type: decision
---
# Decision: the web surface is reachable over Tailscale, always (R15)

**Date:** August 8, 2026
**Topic:** reachability of the operational web surface

## Decision
Every HTTP surface the harness exposes binds all interfaces and is reachable
over the Tailscale network. `serve_site` resolves the host's Tailscale FQDN
(MagicDNS name) at startup, prints it as the canonical URL, and REFUSES to
start when no FQDN exists — unless the operator passes `--allow-no-tailscale`,
which serves anyway and discloses the degraded mode.

## Rationale
- A dashboard that answers only on `127.0.0.1` is invisible from every other
  machine the operator uses; "we have a dashboard" becomes a claim nobody can
  check.
- Tailscale is the fabric these machines already share, so reachability over it
  is the difference between an observability surface and a demo.
- Refusing beats silently degrading: a surface that quietly serves loopback-only
  looks identical to a working one until someone needs it.

## What did NOT change
Authority. The surface stays read-only by construction: GET and HEAD only,
every other method 405, the route table is the built page list so no request
can become a filesystem path, and no page carries a form or a script. Wider
reach, identical authority — the [[20260808-ocaml-only-tooling-rule]] pattern
of enforcing a rule in code rather than in review applies here too.

## Evidence
`Hermes_httpd.parse_tailscale` (pure, CGNAT-range checked),
`tailscale_address`, and `banner`; `test_hermes_httpd` pins the parse, the
non-Tailscale rejection, the refusal case, and a live loopback leg. The FQDN is canonical because an address changes when a node re-registers and
the name does not. Verified live at `http://vm-1.tail55d152.ts.net:8790/`.
