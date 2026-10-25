---
name: smp-concurrency-slice
description: The per-slice workflow for a coordinator-lock / SMP concurrency change in zigvm — measure contention first, shard under a proven total lock order, prove sharded-equals-global, never optimize a lock you haven't measured.
---

# SMP concurrency slice — coordinator-lock elimination workflow

This skill governs any change to zigvm's concurrent scheduler coordinator state
(`SmpEngine`, `L_v`/`L_c`/`L_reg`/`L_timer`/`L_events`, run-queues, parked lists,
ownership, fairness, events). It is the operational discipline under the S-epoch
design (`docs/20260729-051217-s-epoch-smp-coordinator-lock-fractal.md`) and the
STPA safety packet (`SAFETY_ANALYSIS.md` UCA-SMP-9/10/11).

**Read first:** the S-epoch fractal doc, `docs/OTP30_SMP_EPOCH_PLAN.md` (the 6-step
sequence + exit criterion), `skills/stpa-safety-protocol/SKILL.md`, and
`proofs/Scheduler_Signal.v` (the signal-order invariant every step preserves).

## The non-negotiable invariant

> **A single total lock order `L_v → L_c → {L_reg, L_timer} → L_e → L_events → L_sigq`,
> acyclic, no back-edge.** Every acquire on every path (trap / wake / grant / steal / exit)
> respects it. Violating it is **UCA-SMP-9** (an `L_v↔L_c` deadlock → a thread never returns).
> `L_sigq` (per-`Process` signal-queue leaf, Option B / DIVERGENCE 614) is the LOWEST leaf:
> always acquired last, and NOTHING may be acquired while holding it — its critical sections
> are pure `sigq` vector ops with no lock reach.

**Landed state (read before designing):** Option B is LANDED (DIVERGENCE 614, master
`cbf9934`) — `drainSignals`' message bulk runs OFF `L_v` via the `tl_drain_lv` threadlocal
escalation + `L_sigq` batch-detach; `VmLock` is module-scope. The next levers are
per-burst escalation batching and the sender-side `L_v` narrowing (see Gotchas).

## The five-step loop

### 1. MEASURE — attribute the serial term BEFORE touching a lock
There is NO `--smp-contention` harness mode — the measurement is a TEMPORARY probe
(revert it before landing):
1. Flip `src/smp_trace.zig` `enabled = true` (comptime) — the lock hooks compile in.
2. Add a TEMP test that sets `smp_trace.active = true`, runs the ring
   (`seedRing`/`driveThreads`, n=4 × ≥8 seeds), then prints `smp_trace.report(.l_v)`.
3. For a relocation, measure **A/B in one run**: a temp `smp_b_off` switch that restores
   the old lock shape, so before/after share the host and workload.
4. The 16×256ns histogram SATURATES at 3840ns — p99 pins at the cap; read the full
   bucket vector + a bucket-weighted total, and read the ≥3840ns TAIL count (the
   serial-term dominators) separately from the average.
The slice targets the cell that **dominates the Amdahl serial term** — never a guessed
lock. **FM-SMP-CONTENTION-BLIND:** optimizing an unmeasured lock is a wasted slice and a
wrong ordering. Attribute the acquire COUNT as well as the hold — Option B's probe showed
a relocation can halve the long-hold tail while 3×ing acquires (per-arm escalation), a
trade that only message-size scaling justifies; the count told that story, the p99 did not.

### 2. DESIGN the shard + its metamorphic law
De-globalize the cell into per-scheduler state (inbox / counter / ring), merged at a
barrier by stamp order. Write the **`sharded ≡ global`** metamorphic law FIRST: the
sharded implementation must denote identically to the global one — same wake order, same
mailbox FIFO, same fairness bound, `Σ per-scheduler == global` (conservation).

### 3. IMPLEMENT under the runtime lock-order checker
Every `lock()` asserts the target is strictly below every currently-held lock in the total
order. An out-of-order acquire **panics with the offending pair** (UCA-SMP-9 fail-closed —
a deadlock is a panic in test, never a hang). The checker is COMPTIME-GATED
(`smp_trace.enabled = false` by default): for the live positive control + the back-edge
mutant kill, temporarily flip `enabled = true` + `active = true`, run the slice's laws
(green = every acquire path in-order; the seeded back-edge = the named-pair panic), then
revert. Keep the data plane (`ia.run` on the proc's own heap) untouched — the fix is
control-plane only.

### 3b. THREADSANITIZER — the race verdict a green gate CANNOT give
A per-pair-order / torn-queue race is **rare + nondeterministic**; a green suite inspects only the
ONE interleaving that ran, and `checkPerPairOrder` is **blind to a pure drop** (a missing delivery
still ascends). So a green gate is **necessary but NOT sufficient** for any lock-relocation slice.
Run the SMP concurrency laws under **ThreadSanitizer** — it converts the probabilistic race into a
**deterministic** verdict on the first overlapping access:

```sh
# TSan needs the LLVM backend (self-hosted backend ignores sanitizers — CAST-15).
# Detection is by EXIT CODE (66) + the "ThreadSanitizer: data race" line, NOT the
# printed "tests passed" (a CAST-12 verify-by-exit-code case).
CACHE=/tmp/zigvm-tsan-$(printf '%s' "$PWD" | md5sum | cut -c1-12)
ZIG_LOCAL_CACHE_DIR=$CACHE/l ZIG_GLOBAL_CACHE_DIR=$CACHE/g \
  .zig-tools/bin/python3 -m ziglang test -fllvm -fsanitize-thread src/vm_all.zig \
  --test-filter "smp-shard-conservation"      # or e51-t1 / the slice's metamorphic law
# clean == exit 0, no "data race" line. A relocated drain that races append vs
# read/clear is flagged HERE regardless of interleaving luck.
```
Amplify the pressure so the race is reliably reachable (not a 1-in-a-million flake): **yield-widen**
the window (`std.Thread.yield()` between the queue read-advance and the clear, the gap-b-1 pattern),
drive **n∈{1,2,4,8}=MAX_SCHED × ≥8 seeds** on a receive-bearing workload, and keep **conservation
as the drop-net** (a drop is invisible to per-pair-order — only sigq-empty-at-quiescence sees it).
TSan clean + conservation + `checkPerPairOrder` + the PROVEN `Scheduler_Signal.v` invariant (whose
hypothesis the metamorphic law re-validates) is the trust argument; a bare green suite is not.

### 4. PROVE — order + conservation + ≥2 mutants + a seed regression
- **Order law** (`smp-lock-order-total`): drive every acquire path; the order vector never
  inverts. Mutant: acquire `L_c` then `L_v` → the checker reddens (the deadlock, caught).
- **Conservation law** (`smp-shard-conservation`): `Σ per-scheduler cell == global`; a
  pid is runnable on ≤1 scheduler. Mutant: drop/double a merge → conservation fails.
- **Bounded joins**: every concurrency law carries an abort watchdog — a deadlock blows
  the wall bound = a failed law, never a hung suite.
- **Deterministic seed regression** (`smp-interleaving-replay`): the specific race the
  slice fixes is captured as a schedule seed → a permanent regression test.
- **`--verify-formal`** stays green — `Scheduler_Signal.v` signal-order invariance holds.

### 5. RATCHET + safety packet + accept
- Re-measure with `--scale-oracle`: the n=8 efficiency delta must be POSITIVE (the removed
  cell actually moved the serial term — else the slice is inert, revert it). There is NO
  `perf_thresholds.scale_eff_*` ratchet row yet — the run-level BOUNDED band (75–90%
  EQUIV-grade) is the current regression guard; adding a real ratchet row goes through the
  plan-hash machinery as its own slice, NEVER a hand-INSERT into the evidence DB.
- Fill the STPA safety packet (UCA-SMP-9/11 + any new FMEA row) per `stpa-safety-protocol`.
- Green gate + `record_cycle` with the **`smp-lock:` token** in the notes — the ARMED
  `SP-SMP-LOCKGATE` rete rule then requires the law trio (`smp-trace-order` +
  `smp-shard-conservation` + `drainSignals-relocated`) present in the REAL src projection,
  fail-closed. A red gate → a `CAST_LOG.md` cause entry first.

## Gotchas (all documented in the S-epoch fractal + SAFETY_ANALYSIS)
- **Never nest `L_c` inside itself** — `deliverParked*` must snapshot then release, not hold
  `L_c` across `signal` (the non-reentrant self-deadlock).
- **The parked tick is the coupling** — `deliverParked*→signal→applyWake` needs
  `L_v`-protected ownership/timer state; that coupling is WHY `L_v` still exists. Break the
  coupling (relocate the state to `L_c`), not just the lock.
- **A lost wakeup = a hung process** (FM-SMP-SHARD-DROP) — the conservation law is the guard;
  a sharded inbox that drops an item on merge is a hang, caught as a failed bounded-join law.
- **Measure the delta** — a lock change that doesn't move the `--scale-oracle` efficiency is
  inert; do not land it for its own sake.
- **The handover fact-grid can be WRONG — re-verify arm classifications in code.** Option B's
  handover claimed `Signal` had 3 arms; it has SIX, and `.down`/`.link_req`/`.unlink_req`
  mutate `links`/`monitors_held`/`aliases`, which the SEND path (`resolveAliasOwner`, every
  ref-send) and `process_info` read under `L_v` — they must ESCALATE. "Owner-exclusive" is a
  claim about EVERY cross-thread reader, not about who runs the arm.
- **`tl_drain_lv` must be `null` for every drain under a held `L_v`** (the interpret-path
  drains) — the spinlock is non-reentrant; only worker SECTION 2 sets it.
- **All SEND paths still hold `L_v` today** — that is why MUT-SIGQ-4 (unguarded append) is
  EQUIVALENT-today. The sender-side narrowing must solve, in order: (a) the `procs`-array
  deref (reallocs on spawn under `L_v`; boxes are stable — a fixed-root stable index is the
  enabler), (b) the SEND event's `hashTerm` over the TARGET's heap (racing target-side GC,
  which runs under `L_v` — precompute or relocate the hash), (c) shared `drain_scratch_*`
  buffers in `deliverParked*` (currently `L_v`-serialized). Re-arm TSan on MUT-SIGQ-4 the
  moment any sender drops `L_v` — the leaf then becomes load-bearing.
- **A signal-path differential that FLIPS with process structure is a SCHEDULING RACE, not a
  semantic gap — do NOT build a fix for it** (DIVERGENCE 738, `docs/ISSUE_PATTERNS.md`
  SCHED-RACE-DIFFERENTIAL). Before touching `drainSignals`/the exit arms to "fix" a
  link/unlink/exit differential, re-run it main-proc vs spawned-worker and immediate-vs-delayed
  peer exit: if OTP's own outcome flips (linkord survives in the main process, dies 5/5 spawned),
  zigvm's eager drain already matches OTP on the deterministic variants and the residual is
  main-proc scheduler ORDER only — `EQUIV(scheduling)`. The tell of a WRONG fix: it makes zigvm
  SURVIVE more than baseline (a "defer + discard-on-unlink" fix over-discards — it cancels an
  already-sent exit OTP still honours). OTP's `unlink/1` cancels a link-exit ONLY when it reaches
  a still-ALIVE peer; the async unlink protocol modelled single-node is SYNC-MODEL-APPROXIMATION.
  This one was built in full (LAW + 2 mutants + TSan-clean + gate 1080) then reverted.
