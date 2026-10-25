# Link Validation Reference

Use this when validating `*-analysis.html`, `*-deck.html`, `*-index.html`, and `task-<id>-links.json`.

## Link Classes

| Class | Required Evidence | Manifest Status |
|---|---|---|
| Local path | `test -f <path>` | `local_files=verified` |
| Relative HTML link | resolve `href` against `docs/journal/` and `test -f` | `relative_links=verified` |
| Localhost route | `/usr/bin/curl -k -fsS http://127.0.0.1:4200/...` | `verified` or `unavailable_<reason>` |
| Customer Tailscale route | `/usr/bin/curl -fsS https://vm-1.tail55d152.ts.net/c3i/...` | `verified` or `unavailable_<reason>` |
| Internal HTTPS route | `/usr/bin/curl -k -fsS https://vm-1.tail55d152.ts.net:8443/...` | `verified`, `expected`, or `unavailable_<reason>` |

## Validation Commands

```bash
cd /home/an/dev/ver/c3i
jq empty docs/journal/task-<id>-links.json
for f in docs/journal/<slug>-journal.md docs/journal/<slug>-analysis.html docs/journal/<slug>-deck.html docs/journal/<slug>-email.md docs/journal/<slug>-index.html docs/journal/task-<id>-links.json; do
  test -f "$f" || exit 1
done
for href in $(rg -o 'href="[^"]+"' docs/journal/<slug>-index.html | sed 's/^href="//;s/"$//'); do
  case "$href" in
    http*) : ;;
    *) test -f "docs/journal/$href" || exit 1 ;;
  esac
done
```

## Failure Semantics

- If a route check fails, write the exact failure into the manifest.
- If DNS fails, use `unavailable_dns_resolution_failed_<date>`.
- If the service refuses connection, use `unavailable_connection_refused_<date>`.
- If a route is structurally correct but not checked, use `expected_not_verified_current_pass`.
- Never set `verified` unless the check passed in the current pass.

## Working-Link Definition

For git handoff, a link is "working" only if the relevant class works:

- local/static bundle handoff: local paths and relative HTML links pass;
- served handoff: local/static checks pass and HTTP/Tailscale route checks pass;
- degraded handoff: local/static checks pass, failed routes are explicitly marked unavailable.
