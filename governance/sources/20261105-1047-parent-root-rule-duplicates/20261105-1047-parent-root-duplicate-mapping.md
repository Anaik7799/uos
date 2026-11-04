# 20261105-1047 — Parent-root rule duplicate mapping and replacement receipt

#fractal-l0 #fractal-l4 #fractal-l7 #fractal-l9 #zk-adr #zero-muda

Authority: operator directive 2026-11-05 ("fix the parent duplicates too"), continuing the
`SC-MIRROR-PROJ-001` §3 governed pass recorded at `governance/sources/20261105-1025-stale-shadow-rules/`.
Report-only record; grants no admission. Observed host clock: 2026-11-05T10:38:18Z.

## Finding

`/home/an/NAS-setup` is a multi-project umbrella directory (`uos`, `c3i`, `k8s-lab`, `oracles`,
`harness-bionic`, …) with **no `.jj` and no `.git`**: nothing under it is VCS-reversible. It carried a
`.claude/rules/` surface of 7 UOS contract copies plus a `.claude/AGENTS.md`. Because `uos` is a
subdirectory, a Claude session rooted in `uos` loaded **both** the parent copies and the canonical uos
projections — 19,521 B of always-on duplication.

All 7 parent copies are either byte-identical to, or strictly **stale** relative to, the canonical uos
contract. None is scope-specific to the umbrella or to a sibling project.

| Parent copy | Bytes | Relation to canonical | Canonical authority |
|---|---|---|---|
| `dmc-tcm-mandate.md` | 1,833 | byte-identical | `uos/.claude/rules/dmc-tcm-mandate.md` |
| `km-wiki-zk-contract.md` | 1,141 | byte-identical | `uos/.claude/rules/km-wiki-zk-contract.md` |
| `uos-governance.md` | 970 | byte-identical | `uos/.claude/rules/uos-governance.md` |
| `comprehensive-checklist-contract.md` | 4,885 | **stale**: declares "5-Domain, 18-Item" and omits Domain 6 Provenance & Admission Integrity entirely; cites retired `tools/uos doctor` | `uos/contracts/rules/comprehensive-checklist-contract.md` |
| `tailscale-web-fqdn-mandate.md` | 2,294 | **stale**: advertises peer port `8088`, which N01 corrected to `4100`; omits the peer diagnostic routes; cites retired `tools/uos` CLI | `uos/contracts/rules/tailscale-web-fqdn-mandate.md` |
| `full-symbiosis.md` | 5,810 | **stale**: pre-`20261001-1117` text, superseded by the dated UOS adapter whose own header marks the earlier text inert historical evidence | `uos/contracts/rules/full-symbiosis.md` |
| `timestamp-mandate.md` | 2,588 | **stale**: cites retired `tools/uos timestamp-check` instead of `tools/uos-cli timestamp-check` | `uos/contracts/rules/timestamp-mandate.md` |

The stale copies were not merely redundant, they were **misleading**: an agent reading the parent
checklist would run a 18-check gate believing it complete while Domain 6 — the anti-laundering domain
that exists because of the 2026-09-07 coordinator forgery — was absent from its instructions.

## Action

1. All 7 parent rule bodies and `/home/an/NAS-setup/.claude/AGENTS.md` preserved here as
   `*.parent-preserved` with `manifest-md5.txt`. Preservation is inside the versioned uos tree
   precisely because the parent root has no VCS of its own. Nothing was deleted.
2. The 7 parent rule bodies replaced by a single pointer,
   `/home/an/NAS-setup/.claude/rules/00-canonical-uos-contracts-pointer.md`, which names the canonical
   uos contract paths and states that the umbrella root holds no independent policy.
3. No canonical uos contract text was edited. The four governed uos vendor mirrors
   (`.claude`, `.codex`, `.gemini`, `.agents`) are untouched and remain name-set isomorphic at 77 files;
   `SC-MIRROR-PROJ-001` §2 and §4 are unaffected, since the umbrella root is not one of the four
   governed surfaces.

A session rooted at the umbrella is left pointed, not blind: it receives the pointer and the canonical
paths rather than a stale copy.

## Limits

EV ceiling 93; `EV-94..109` `NOT_ADMITTED`; no new EV number minted. `/home/an/NAS-setup/CLAUDE.md`
(18,745 B, asserting `EV-01..EV-99 admitted` and `CURRENT EV-CYCLE: EV-108`) is a **separate** finding
and is NOT addressed by this pass; it remains loaded and still contradicts `SC-PROVENANCE-001`.
This receipt is documentary; it establishes no runtime enforcement and no admission.
