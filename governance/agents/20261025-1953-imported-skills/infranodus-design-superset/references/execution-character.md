# Approach B Execution Character and Assurance Envelope

This contract governs the high-frequency journal/design bundle path. Its
semantic source is OCaml; prose describes the executable laws and may not
weaken them.

## Character

`Swiss` means precise, restrained, modular, inspectable, repairable, and
dependable. `ZERO-MUDA` means each source is acquired once per run, the HTML
projection is rendered once, identical bytes are atomically fanned out, and an
unchanged wiki corpus reuses a content-addressed projection. Concurrency is
bounded and deterministic; the sequential interpretation remains the oracle.

## Typed pipeline

```text
Prompt_chain × Artifact_set × Wiki_corpus × Bundle_spec
                  │ smart constructor: accumulate every violation
                  ▼
         bounded parallel acquisition
                  │ parallel result ≡ sequential result
                  ▼
      content-addressed wiki projection cache
                  │ input fingerprint binds every acquired byte
                  ▼
           exactly one HTML projection
                  │ same byte value
           ┌──────┴──────┐
           ▼             ▼
      repository      dashboard
           │ atomic publication
           ▼
 TUI × dashboard × metrics × OTEL file log × Playwright evidence
```

## Hard controls

- Manifest schema version is explicit; unsupported versions fail closed.
- Durable artifacts may not resolve under `/tmp`; missing and duplicate paths
  are accumulated as typed violations.
- Prompt ledgers are either legacy ordered records or explicit contiguous
  ordinals. Mixing schemas or skipping an ordinal fails closed.
- Publication is prepare-then-rename. Every target receives the same HTML
  value; unchanged targets are not rewritten.
- The sequential and bounded-parallel acquisition interpretations must be
  observationally equal and preserve manifest order.
- Every human timestamp emitted by this path has the exact
  `yyyymmdd-hhss` / `YYYYMMDD-HHMMSS` form. OpenTelemetry uses Unix nanoseconds
  because that protocol requires them. Immutable historical filenames are
  evidence and are not renamed. Delivery additionally requires the repository
  `--check-time` NTP/host-clock gate.
- Stage budgets are fail-closed: decode 100 ms, validate 250 ms, materialize
  1000 ms, acquire 2000 ms, wiki 30000 ms, render 2000 ms, publish 2000 ms,
  and report 500 ms. A cache-hit warm path must finish in less than 1500 ms.
- The observation plane is read-only and report-only. It cannot write gate
  evidence or upgrade a parity verdict.
- Typed OCaml Playwright verifies the archival page and status dashboard over
  mobile, tablet, desktop, and large viewports; console/page errors, horizontal
  overflow, missing prompt provenance, missing budget columns, remote runtime
  assets, or incomplete stage rows fail the UI check.

## Fractal quality envelope

| Scale | Carrier | Required observations |
|---|---|---|
| operation | one decode/read/render/write | total result, duration/budget, byte count, named error |
| stage | ordered operation fold | exactly one start and terminal event, work, bytes, domains, complexity |
| bundle | validated manifest and acquired corpus | prompt/artifact totality, one render, identical fanout, cache identity |
| UI | archival page and live status dashboard | legibility, responsive non-amputation, no remote runtime dependency |
| knowledge | Markdown, self-contained HTML, wiki/ZK graph | source equivalence, links, backlinks, artifact and prompt provenance |
| system | OODA publication controller | fail-closed controls, advisory observation, residual preservation |

Every scale crosses the same vectors: correctness, performance, dependability,
durability, security, accessibility, information quality, human orientation,
observability, evolvability, and upgrade compatibility.

## Assurance lenses and authority boundaries

| Lens | Application | Authority |
|---|---|---|
| ADD algebra | initial sequential acquisition versus final bounded parallel interpretation; publication homomorphism | hard law |
| declarative zero-trust rules | eventual cycle admission consumes real gate facts; the bundle never self-attests or writes a green stamp | external hard gate; no new doc-coupled rule |
| STPA + FMEA | missing, wrong, stale, or prematurely stopped publication; cache, schema, clock, budget, and atomicity failures | safety constraints and hard local laws |
| ACH | H1: patching Approach A is sufficient; H2: recurrent multi-profile work needs Approach B. Repeated render, temporary evidence, and fragmented verification disconfirm H1 | decision support from graded evidence |
| Admiralty | fresh source/tests at the current worktree are A2 until canonical-gate/HEAD admission; single-host timings are B2 | freshness/reliability bound |
| Stan | no new model: this slice lacks a uniquely Bayesian question needing a posterior. Existing Stan surfaces may annotate the wider decision from real ledger data | advisory only, never a gate |
| devil's advocate | challenge monolithic manifests, whole-corpus cache invalidation, digest/authenticity confusion, single-host timings, and observation-plane write amplification | mandatory challenge record |
| reality check | the bundle publication pipeline is implemented; full InfraNodus behavioral/pixel parity, all 115 Figma components, and live Stitch/Figma round-trip remain open | bounded completion claim |

New identity is SHA-256 fixity, not a cryptographic signature, trusted
timestamp, WORM guarantee, or authenticity proof. Historical MD5 is accepted
only by the explicit read-only legacy decoder.

## Rot and upgrade resistance

- Schema changes add a new decoder/version and a migration law; they do not
  silently reinterpret version 1.
- Every performance optimization must preserve sequential/parallel equality
  and output-byte equality.
- Tests cover laws, negative mutants, property samples, BDD warm-path behavior,
  responsive UI observations, and live route delivery.
- Dashboard and OTEL schemas are versioned observations. Unknown fields remain
  ignorable; required fields remain tested.
- Any failure involving the judge, evidence path, cache truth, or clock follows
  the repository CAST-before-rerun protocol.

## Reality-check summary

Approach B removes repeated HTML rendering and centralizes bundle knowledge in
one validated value. It does not make the wider InfraNodus parity program
complete. Its strongest current evidence is executable OCaml law and browser
evidence; its weakest evidence is performance generalization beyond this host
and all external Figma/Stitch deployment state. Keep those residuals visible.

## Long-term PKM preservation profile

The bundle report is an OAIS-inspired projection: prompt/source/artifact input
is the SIP; self-contained HTML plus SHA-256 fixity is the AIP; archival routes
and wiki/browser interpretations are DIPs. SHA-256 is recomputed over every
copy every run and fanout inequality fails closed. This does not claim full
OAIS certification, trusted signatures, WORM storage, geographic replication,
or periodic background scrubbing.

Journal capture promotes to one-idea zettels, then to wiki/Maps of Content,
without deleting provenance. New notes use versioned YAML frontmatter, stable
`YYYYMMDD-HHMMSS`-prefixed IDs plus collision suffixes, typed reciprocal links,
and a Dublin Core mapping. Open files are authoritative. Obsidian/Logseq,
PDF/A, DOI, ORCID, Crossref, BagIt, and physical paper are optional external
interpretations only when real consumers and evidence exist. Canonical detail:
`docs/PKM_ARCHIVAL_ARCHITECTURE.md`.
