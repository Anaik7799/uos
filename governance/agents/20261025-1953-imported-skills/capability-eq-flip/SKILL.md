---
name: capability-eq-flip
description: Raise an EQUIV capability toward EQ by finding and fixing FM-DISPATCH-DEAD (handler-proven-but-undef) functions and wiring them to byte-EQ against pinned OTP-30. Use when working a `capability_features` EQUIV row (open_port, hot_code_load, tracing, erl_cli, file, crypto, sockets, code, …), when a compiled `M:F/A` returns `undef` despite a green handler law, or when narrowing an EQUIV remainder. This is the concrete slice-mechanics companion to production-readiness (which picks WHICH axis) and otp-conformance-protocol (which keeps verdicts honest).
---

# Capability EQ-flip — the FM-DISPATCH-DEAD sweep & wire workflow

This skill distills the workflow that flipped/narrowed ~7 capabilities in one
session (DIVERGENCE 582–601) and surfaced the **most frequent bug class in the
codebase**: `FM-DISPATCH-DEAD` (19 instances / 16 DIVERGENCE entries — canonical tally in `docs/ISSUE_PATTERNS.md`, incl. the via-APPLY sub-mode, entry 650). A capability is claimed "wired"/EQ
because a *handler-level* law is green, but the compiled `M:F/A` a real beam emits
resolves to `undef`. This skill makes the compiled surface real and byte-EQ.

**Read first:** `docs/ISSUE_PATTERNS.md` (FM-DISPATCH-DEAD + HANDLER-PROVEN-NOT-DIFFERENTIAL
+ the gotcha patterns), `production-readiness` (axis routing), `otp-conformance-protocol`
(verdicts rise only by fixing). This skill is the per-slice mechanics under them.

## The five-step loop

### 1. SWEEP — find the dead/undef functions (never trust the ledger's "proven")
Compile a probe that calls each library function of the capability's module surface
**with DIRECT static calls** and run it on zigvm; `undef`/`badarg` where OTP succeeds
is a dead arm. Also probe the pinned OTP oracle for the exact return shapes.

```erlang
-module(probe). -export([t/1]).
t(1) -> erlang:display({f, catch mod:fn(Args)});   % one clause per function
```
```sh
zig-out/bin/zigvm run probe.beam t 1                 # zigvm
third_party/otp/bin/erl -noshell -pa DIR -eval 'probe:t(1), init:stop().'  # oracle
```
- **Prefer DIRECT `mod:fn(...)` calls in probes** (not `apply(mod,F,Args)`). NOTE:
  since DIVERGENCE 650 dynamic `apply` DOES consult `resolveLibrary` (dispatch.zig's
  `resolveDynamic = resolve ∪ resolveLibrary` injected as `native_bif_resolver`), so
  apply no longer under-reports wired functions — but direct calls remain the clean
  probe that also exercises the compiled `call_ext` path a real beam emits.
- The handler often ALREADY EXISTS (a `doFn`/BifFn/`code_index` method proven by a
  law that calls it directly). The gap is dispatch reachability, not logic.

### 2. WIRE — make it reachable from a compiled beam
zigvm has three resolvers in order: `resolve()` → `resolveLibrary()` → `call_ext_code`(→undef).
- `resolve()` reaches `implOf` **ONLY** for a bif.tab `.implemented` row.
- `resolveLibrary()` (src/bifs/dispatch.zig) is for erlang.erl-style **library wrappers**.
Put the wrapper in `resolveLibrary` (non-erlang modules **before** the
`if (!eql(module,"erlang")) return null` guard; erlang wrappers **after**). If it
needs Vm state (a table/port/pattern), the BifFn sets `m.pending = .{ .foo = … }` and
a `proc.zig` handler serves it — remember to add the pending variant to
`instr_algebra.zig`'s `actionTermOrNil` (exhaustive switch → "must handle all
possibilities" otherwise). **Add the function to the dispatch-reachability MANIFEST**
(`LAW dispatch-reachability MANIFEST` in dispatch.zig) — this is the standing guard.
- **Module-name mismatch trap (#9):** if a verb has both an `erts_internal:` primitive
  and an `erlang:` auto-import, wire the **`erlang:` name** (what user code calls).

### 3. PROBE the contract — get the EXACT shapes, including the boundaries
Byte-EQ needs the precise term shape: proplist ORDER and element count (`trace_info(all)`
= 7 items in erts order), the `[]`-vs-`false` distinction (an enabled trace's
`match_spec` is `[]`, not `false`), atom-vs-tuple, host-independence (paths like
`code:which/1` are host-specific → a documented bound, not EQ). RAISE vs RETURN: most
`erlang:` BIFs RAISE `error:badarg` on a bad arg (route a handler's `error.Badarg`
through `raiseErrorAtom` in the pending arm); most `gen_tcp`/`file` ops RETURN `{error,_}`.

### 4. DIFFERENTIAL + LAW + ≥2 MUTANTS
- A **durable compiled differential** `fixtures/erl/zigvm_<cap>_diff.erl`, run on both
  VMs, byte-EQ. A handler law is INSUFFICIENT evidence (Rule 9). Invoke with `run BEAM t N`
  (a single int arg) — **never pass multi-token args via an unquoted `$VAR`** (the
  sandbox exec collapses argv → HARNESS-ARGV-ARTIFACT; verify with `/proc/self/cmdline`).
- A **deterministic in-process LAW** (drive the handler directly, no boot/CLI path) so
  the semantics are proven independent of any harness flake.
- ≥2 mutants, each killed by the LAW (a boundary mutant + a dispatch-dead mutant that the
  MANIFEST reddens). Fresh unique cache dir per mutant (CACHE-STALE-MUTANT); a killed
  mutant prints `--seed=<hex>`. `git checkout <file>` REVERTS uncommitted work — use
  Edit-to-revert or a `/tmp` backup.

### 5. FLIP or NARROW — honestly
- Flip the `capability_features` row to `"EQ"` only at **core-complete + bounds-documented**
  (the gen_tcp precedent: EQ-with-documented-bounds is the norm). Rebuild the harness,
  `--capability-ledger` shows the new count, `--production-readiness` {C}. **Verdicts rise
  only by FIXING, never relabel** (conformance Rule 2/9).
- If a real remainder stays (release_handler, an expr evaluator, host-specific paths),
  keep it **EQUIV** and narrow the ledger prose. Honest EQUIV beats a fabricated EQ.

## Always update (the fractal tail)
DIVERGENCE_LOG (a new entry), MUTATION_LOG (the killed mutants + seeds), ISSUE_PATTERNS
(bump FM-DISPATCH-DEAD's instance table + count; add a new pattern if novel),
SAFETY_ANALYSIS (FM-DISPATCH-DEAD count / any new FMEA row), CAPABILITY_STATUS, the KPI
dashboard, and the handover memory. Finish on a green canonical gate and cite it.

## Gotchas that have bitten (all in ISSUE_PATTERNS)
- **Gate red on a codegen-freshness stale** (lean/rocq/quint) after a machine toolchain
  bump — a version comment only. Fix: `--codegen-lean` (etc.) + commit; not your slice.
- **`erlang:halt()` from a fixture races zigvm's output flush** → use `init:stop()`.
- **A stale `erl_crash.dump` + un-timed `erl` in a bash loop hangs the tool call** →
  `rm -f erl_crash.dump` + `timeout N` the `erl` side.
- **`zigvm run` appends the fn-return** (e.g. `true`) after display output → strip it.
