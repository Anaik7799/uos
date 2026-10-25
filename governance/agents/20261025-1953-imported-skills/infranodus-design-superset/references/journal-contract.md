# Journal and Knowledge Contract

Use the 13-section journal protocol, then add knowledge-graph, functional
design, Bonsai, verification, and skill-promotion appendices when applicable.

Preserve user prompts as immutable JSONL. Do not normalize spelling,
whitespace, repetition, or order. Link continuation ledgers instead of editing
an earlier ledger. Hidden model chain-of-thought is not a journal artifact;
record reproducible decisions, assumptions, evidence, and residuals.

Markdown carries frontmatter, wikilinks, typed relations, tags, source paths,
and current verification status. HTML embeds inline CSS, all prompt/text
artifacts, selected images as data URIs, and no remote runtime resource. It
must pass the typed OCaml Playwright viewport matrix. Wiki anomalies remain
report-only and cannot mint or revoke gate evidence.

New content/cache/report/transaction identity is SHA-256. Publication uses the
project OCaml prepare/commit/recover transaction: serialized fanout,
per-target atomic replacement, fsynced recovery evidence, and one content ID.
Do not claim simultaneous cross-target atomicity. Historical MD5 is accepted
only through the explicit read-only legacy decoder.

Every journal entry MUST also publish a canonical Tailscale FQDN path in
frontmatter (`tailscale_fqdn`) and in the rendered body. The path must be
validated through typed OCaml Playwright before being reported as live:
observed title must equal the declared title, SHA-256 of the served response
body must equal SHA-256 of the local archive, the prompt-chain observation must
be present, and the four-viewport violation set must be empty. HTTP status is
transport feedback only; a dashboard fallback may return 200 for an absent
leaf and is never identity evidence. A local filesystem path remains required
as provenance and byte oracle, but is never a substitute for the FQDN. If
publication is unavailable, record
`Unavailable_observed` with the exact failed route and reopen evidence; never
invent a URL.

Journal timestamps and filenames use `YYYYMMDD-HHMMSS`, derived only after
the NTP/host-time check. Protocol-native telemetry timestamps remain Unix
nanoseconds.
