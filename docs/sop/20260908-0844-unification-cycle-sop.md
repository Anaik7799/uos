# Bounded unification reviews for SDLC and SRE

Observed: 2026-09-08T08:12:44Z. #fractal-l0 #fractal-l4 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

Use this SOP with the [12-stage manual/agent release runbook](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-unification-20260908-0753/docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md) and [17-aspect matrix](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-unification-20260908-0753/docs/reviews/20260908-0551-release-17-aspect-and-source-review.md).
It is repository-local guidance and tooling; integration/admission is separately controlled.

| Stage | Required action and evidence | Stop condition |
|---|---|---|
| Intake | Canonical Sa-plan plan/task/attempt, scope, current clock and exact source | Unknown authority, stale evidence, competing effect owner |
| Freeze | Snapshot owned JJ files before any stale-workspace operation; retain source hashes | Concurrent rewrite or missing files; preserve both versions and recover separately |
| Select | Hard constraints first, then dependency eligibility and C × STPA × FMEA × dependency × impact | Invalid or unknown factors cannot become zero; blocked deployment stays blocked |
| Observe | Bounded board inbox and Zenoh metadata snapshots; retain freshness and digests | Peer text is never executable authority or a verified capability |
| Test | Typed output contracts; meaningful invalid, stale, tampered and timeout cases | Labels, substring checks and HTTP200 alone do not establish correctness |
| Browser/TUI | Same immutable release and explicit real/test/unavailable meaning | An unknown physical input must remain UNKNOWN; simulated values cannot enter real evidence |
| Publish | Own namespace and immutable original receipts, byte-preserving envelope and SHA-256 | PUT success without exact readback is incomplete delivery |
| Repair | Record causal mechanism, repair narrowly and rerun affected checks | Never rewrite a failed receipt as a historical pass |
| Recover | Stop only owned staging by checked unit identity and current fence | No generic process killing, production cutover or shared journal regeneration |
| Close | All receipts retained, 13-section journal, residuals and scoped Sa-plan completion | A completed review is not whole-system admission or continuous swarm monitoring |

A review cycle is a bounded observation and decision, not necessarily a code change. Observation dependencies may complete with a failure so unrelated safe checks continue. Release dependencies still require passing evidence. Scope applies to static, structural, dynamic, control, data, wiki, KM and ZK domains and L0–L9; the all-17 inventory is not 17/17 proof.

The [executable design](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-unification-20260908-0753/docs/design/20260908-0701-thirty-unification-cycles.md) defines the denotation and risk selector.
Three independent finite transition models cover338 cases; the cycle selector has100 independent OCaml/Mojo cases. Shared operational code gives both frontends the same effects and errors; it does not independently verify itself.

## Native commands

Run from the owned repository workspace with the existing pinned OCaml environment.

```text
ocaml -I tools tools/unification_cycles.ml selftest
ocaml -I tools tools/unification_cycles.ml repair-tests
ocaml -I tools tools/unification_cycles.ml risk-check --all
ocaml -I tools tools/unification_cycles.ml listen
ocaml -I tools tools/unification_cycles.ml verify-integrity ORIGINAL_RUN
ocaml -I tools tools/unification_cycles.ml receipt-faults ORIGINAL_RUN
ocaml -I tools tools/unification_cycles.ml verify-reconciliation ORIGINAL_RUN LOSSLESS_MIRRORS
```

Mojo accepts the same arguments:
```text
/home/an/.pixi/bin/pixi run --no-install --frozen --manifest-path /home/an/NAS-setup/uos/services/inference/max/pixi.toml mojo tools/unification_cycles.mojo COMMAND ARGUMENTS
```

The run command is intentionally bound to this plan, worker, attempt and session. A new run needs its own canonical task and namespace binding; do not reuse operation IDs for changed payloads. The tool does not create a shadow scheduler or a permanent daemon.

`verify-run` strictly requires the original mirrors to pass. `verify-integrity` independently checks original receipt/order/hash/priority integrity while reporting transport HOLD when any original mirror failed. `verify-reconciliation` additionally checks30 new byte envelopes against original records and fresh live Zenoh readback. A transport repair leaves original cycle statuses unchanged.

The risk tool rebuilds the repository-owned validation source in a bounded private directory. It binds source bytes and the already-installed SQLite/GMP runtime bytes, using local link aliases solely inside that build directory. No package is installed by this build. Missing runtime libraries fail closed. Fresh installations remain Nix/devenv work with a reviewed dependency closure.

## Dependency and egress discipline

Install packages/Python only via pinned Determinate Nix or devenv. Existing Mojo/Python is reused without installation. The optional risk dependency recipe is in `ops/release/flake.nix#risk-checker`; its complete closure was not available on this host and bootstrap remains HOLD.

Observed exception: a Nix build with `--offline` still launched fixed-output source downloads to public origins and failed. Therefore `--offline` is not an egress boundary. Before realizing a closure, inspect the missing outputs/build graph without starting builders; use already-realized outputs or an authorized Tailscale source/cache gateway and controlled build networking. Do not repeat an uncached build merely because the flag says offline.

Manual/agent HTTP, remote hosts and private staging URLs use Tailscale FQDNs. A local private resolver does not prove remote reachability. A public OpenRouter client is not compliant with the FQDN-only rule; Gemma4 advice remains pending a permitted gateway.

## Reviewable decisions and forecasts

Record goals, evidence, chosen action, alternatives, uncertainty, expected result, falsifier and residual risks. This is a reviewable decision summary, not private model reasoning or a consciousness measure.

STPA constrains unsafe control actions. FMEA ranks severity, occurrence and detection difficulty. STM/task leases fence effects. Rete and forecasts advise or veto. Predictive probability requires a precommitted event/horizon, provenance, later outcomes and calibration; fixed demonstration values do not qualify. This run used an ordinal risk rule, not a trained forecasting policy or a claim of globally minimal intelligence cost.


<details><summary>Verification checklist — five domains, 18 checkpoints</summary>

| Domain | Checkpoints | Scope |
|---|---|---|
| Metadata and navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Timestamp, full Tailnet links, tags and evidence references |
| Purity and storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | Existing runtimes only; no drive operations |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Scoped test receipts; broader gates remain unverified |
| Runtime and observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | Distinguish actual process observations from simulations |
| Governance and JJ | CHK-17-SOV, CHK-18-JJ | Independent admission outstanding; isolated JJ work |

No row grants a passing global checklist. Consult the revision-bound verification receipt.
</details>


