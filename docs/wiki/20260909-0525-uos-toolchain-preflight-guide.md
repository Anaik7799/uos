# UOS Operator Guide: Toolchain Preflight

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l7 #zero-muda #tailscale-web #checklist-nav #km-triad #algebraic-atlas #denotational-intent #formal-lean4 #toolchain

**UOS / Wiki / Operator Guide** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
**Contract Reference:** `SC-NIX-DEVENV-001`, `SC-TOOLCHAIN-INPROJECT-001`, `SC-JIDOKA-001`
**Sole Execution Authority:** `sa-plan` (`uos-nix-devenv-toolchain-20260908`)
**Live document:** [http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260909-0525-uos-toolchain-preflight-guide.md](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260909-0525-uos-toolchain-preflight-guide.md)

---

## 1. What it is, in one sentence

`tools/preflight` answers one question — *is the toolchain this repository declares actually present, in the right place, tracked, and working?* — and refuses to answer it optimistically.

## 2. Daily use

```bash
bash tools/preflight                 # ~4.5s, six arms, table on stderr
bash tools/preflight --json          # uos.preflight.v1 on stdout
bash tools/preflight --full          # + nix flake check and devenv test
bash tools/preflight --receipt       # write var/preflight/latest.json
bash tools/preflight --max-age 900   # cheap: is there a recent PASS?
bash tools/uos-cli gate G-PREFLIGHT  # the SDLC gate; runs the above
```

Exit 0 only if **every** arm passes. There is no partial credit.

## 3. The six arms, and why each exists

| Arm | Asks | Exists because |
|---|---|---|
| `resolver` | presence, locality, BEAM | a toolchain resolved from `$HOME` or an evidence tree is barred by invariant 1 |
| `useable` | **does it run?** | `test -x` cannot tell a working binary from a broken one |
| `wrapper` | do `tools/{quint,z3,lean,lake}` work? | a wrapper can front an absent binary |
| `tracked` | is it in Jujutsu? | a tool living only in a working copy is a local artefact, not tooling |
| `parity` | do the OCaml and shell tables agree? | two sources of truth drift silently |
| `identity` (`--full`) | is it the pinned *derivation*? | 29.0.5 and 29.0.6 both report OTP release `"29"` |

## 4. Reading a failure

```
useable    npm            FAIL   exit 7: … Cannot find module 'semver/functions/satisfies'
parity     ocaml-table    FAIL   preflight command did not run
```

Two arms firing on one cause is normal and useful: it tells you the fault is upstream of both. Every failing arm is named — the composite never reports only the first, and that is a proved law (`L7`, `meetAll_fails_of_mem_fail`).

## 5. Receipts and the `--max-age` shortcut

`--receipt` writes `var/preflight/latest.json` plus a timestamped copy: status, per-arm rows, the JJ revision, and the **sha256 of both the checker and the resolver table**.

`--max-age N` reads that record and answers *"is there a recent PASS?"* **without executing anything**. It refuses in four situations:

| Situation | Message |
|---|---|
| no receipt | `NO RECEIPT at var/preflight/latest.json` |
| older than N | `receipt STALE (…s > Ns)` |
| checker or table edited since | `receipt INVALID -- checker changed since it was written` |
| cached verdict was FAIL | `last receipt is FAIL` |

The third is the subtle one. A cached PASS is evidence about *a specific checker reading a specific table*; if either changed, the receipt would be lending its confidence to code it never examined.

## 6. Where it runs without being asked

- **SDLC** — `G-PREFLIGHT` **executes** the preflight (it does not stat the script) and runs **first** in `uos-cli verify-all`.
- **SRE** — receipts under gitignored `var/preflight/` are a durable, scrapeable `uos.preflight.v1` record.
- **Agentic** — `SessionStart` / `PreInvocation` hooks on `.claude`, `.agents`, `.codex` try the receipt first and re-run the sweep only when it is missing, stale, or foreign.
- **Coordination** — `SYNC-13` obliges every agent to preflight before claiming a task or producing evidence.

## 7. Adding a tool

1. Add the arm to `uos_tool_path` in `tools/lib/uos-toolchain.sh`.
2. Add the **same** arm to the OCaml table in `tools/release_process.ml` — `tool_table_parity` will fail closed until you do.
3. Add a `pf_probe` line. **Prefer a functional probe**: make the tool do its job (compile, run, solve, typecheck). Use a version string only where a functional probe would cost more than it proves.
4. Declare `out` or `silent`. `silent` is a trust decision and must be paired with a separate artefact assertion.
5. Run `bash tools/preflight` and then **break it on purpose** to confirm the new arm can fail.

> A probe you have never seen fail is a claim, not a control. `npm --version` answered `9.2.0` for as long as anyone cared to ask, while the install had been incomplete since the day it was made.

## 8. The formal layer

| Question | Answered in |
|---|---|
| What does an observation *mean*? | `preflight_algebra.mli` — the semantic domain |
| Are the algebra's laws true? | `Preflight_Verdict_Algebra.lean` — no `sorry`, axiom audit printed |
| Are they live, or decoration? | 27-law suite + mutation tests M1–M4 |
| Can a caller accept a cached verdict it shouldn't, across interleavings? | `preflight_receipt.qnt` — Apalache `NoError` |
| Why bother with any of it? | [[wiki:20260909-0525-uos-toolchain-preflight-guide]] §9 and the design spec |

## 9. The one idea worth carrying elsewhere

Three passes produced the same defect three times: `otp_release` could not separate two builds, `test -x` could not separate working from broken, exit status could not separate doing the job from doing nothing. Each was the obvious API, and each had an **output space coarser than the property being enforced**.

Before trusting any check, ask what its observable can and cannot distinguish. Then break it and watch.

---

**Related:** [[zk:20260909-0525-adr-096-toolchain-preflight-denotational-semantics-and-verdict-algebra]] · [[wiki:20260908-0927-uos-provenance-integrity-and-km-gate-guide]] · [[wiki:20260908-1345-uos-intent-based-config-and-algebraic-atlas-guide]]
**Design spec:** [20260909-0525-preflight-denotational-spec-and-algebraic-atlas.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0525-preflight-denotational-spec-and-algebraic-atlas.md)
**UOS footer:** `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:8088` · OTP 29 pinned at `…-erlang-29.0.5` · Sa-plan is the sole execution authority; this guide grants no admission.
