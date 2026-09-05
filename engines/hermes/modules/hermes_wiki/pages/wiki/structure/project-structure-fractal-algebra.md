---
id: hermes-project-structure-fractal-algebra
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [structure, workspace, algebra, laws, muda]
created: 2026-08-09
last_verified: 2026-08-12
verified_by: agent
next_review: 2026-09-09
---
# Project structure — fractal algebra

The workspace's laws, and the two operations that change it. Carrier: the
set of paths; every law names the check that holds it.

## 1. The laws

| Law | Required invariant | Live observation (2026-08-12) | Held by |
|---|---|---|---|
| **SW1 partition** | every path lies in exactly one stratum | **Partial:** the six roots hold, but build-excluded auxiliary roots remain outside their path boundaries | scan policy + explicit residual below |
| **SW2 direction** | wiki never depends on parity-harness libraries | **Holds at the named boundary;** this does not make wiki the minimal component or standalone-liftable | `test_hermes_wiki` name guard + Dune graph |
| **SW3 scan closure** | nested Dune stanzas outside `modules/` are data | **Holds:** the root `data_only_dirs` is the outermost gate | tracked root `dune` + toolchain scan |
| **SW4 ledger totality** | every governed entity is classified by its owning ledger | **Partial workspace-wide:** feature/import/legacy ledgers are scoped; auxiliary roots are not covered by one total ledger | register, `Import_coverage`, root-file map |
| **SW5 window disjointness** | FPP base-id windows never overlap | mechanically gated | `hermes_fpp_window_authority` and solver/law suites |
| **SW6 pin locality** | each pin lives with the component it gates | **Pin locality holds; standalone wiki liftability does not** | wiki `baseline/`; dependency closure below |
| **SW7 history append-only** | journals and parked legacy are records | governed | R16 + `Journal` prefix law |

**SW6's two halves came apart (2026-08-11).** Pin locality still holds:
every pin is in `baseline/` inside the wiki. The *contract* it was
written to serve — that the wiki lifts out intact — does not.
`modules/hermes_wiki/src/mbse/dune` requires `hermes_sysml` and
`modules/hermes_wiki/src/fpp/dune` requires
`hermes_fpp_window_authority`. Both are `src` edges. The self-containment
law greps each wiki dune for `hermes_harness_*` and is silent about any
other component, so these two arrived without tripping it. Lifting the
wiki today means lifting three components. Either the two edges are cut
or the contract is restated; recording it is not a substitute for that
choice.

**SW1 has a disclosed hole (observed 2026-08-11, re-censused
2026-08-12).** `generated/`, `rust/`, `scripts/`, `ui_web/`, `webedit/`,
`tools/`, `providers/` and `_gospel/` are deliberately excluded by
`data_only_dirs`, but exclusion is a build property, not a W1
classification. Local environments, build products and loose root artifacts
add runtime residue. §3's clearance below swept the root OCaml fleet; it did
not establish a total ledger for these other roots. SW4 inherits that
workspace-wide residual while its three scoped ledgers continue to govern
their own carriers.

## 2. The operations (both deliberate, never ambient)

- **`promote : projects/X → modules/X`** — defined only when X has a green
  battery, register rows with live probes, a reserved FPP window, and logs
  through the shared OTel/fractal modules. The workspace mirror of a
  `Guarded_cmd`.
- **`park : X → zigvm_legacy/`** — defined only when the map records every
  moved file first. Parking without a map entry is unrepresentable in
  practice: the map IS the undo record.

## 3. Muda, named and removed (the 2026-08-09 clearance)

| Waste (muda) | Instance found | Removal |
|---|---|---|
| defect risk | `dune-project`/`dune` untracked — the build's root could vanish silently (it DID, mid-battery) | tracked; workspace renamed `hermes_workspace` |
| over-scan | dune evaluating broken legacy (`ui_web`) forever | SW3 closure; full build now exits 0 |
| misdirection | root README describing the zigvm harness | parked; the README now maps THIS workspace |
| stale identity | `zigvm_harness` package name + orphan `.opam` | renamed; `sa_plan` public_name updated; `.opam` parked |
| scattered motion | agent code in three root dirs + its docs in three more | consolidated under `projects/ocaml_agent/` |
| unmapped inventory | 384 root OCaml files (earlier today) | mapped, deduplicated, parked — the root holds zero |
| duplicated truth | hand-written counts in docs | derived: register, census, dashboard — documents cite, never restate |

The standing law: **muda-freedom is SW1 + SW3 + SW4 together** — everything
is somewhere, only production is scanned, and nothing is unclassified.

Part of [[Knowledge fractal map]].
