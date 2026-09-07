# 20260907-1420 — OTP 29 web runtime component staging

#fractal-l1 #fractal-l4 #fractal-l8 #zk-adr #zero-muda #tailscale-web

**UOS / Runtime / Staging** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Mirage](http://nas-1.tail55d152.ts.net:4100/mirage) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Observed on nas-1, 2026-09-07T14:34:20Z. Latest checked chrony observation at 14:27:49Z: normal, host 0.755 ms fast of NTP. UTC timestamps, elapsed monotonic time and Lamport counters are separate measurements.

[Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1420-web-runtime-component-staging.md) · [Raw](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1420-web-runtime-component-staging.md) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1420-web-runtime-component-staging.json) · [Work order](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260907-1420-mirage-security-work-order.json). New document routes become available after integration.

## 1. Scope & Trigger

Execute `RUNTIME-PREP` in Sa-plan `uos/mirage-security/20260907-1310`: create an observable, bounded primary/backup launch recipe using actual OTP 29. This is component staging before the integrated-candidate `OTP29-STAGE` and Claude-owned cutover. The mandatory Solo5 upgrade and authenticated-ingress repair proceed as separate tasks.

## 2. Pre-State Assessment

Production port 4100 was served by PID 3243794 on OTP 27. Runtime identity and startup validation were frozen at `f734f8fb82c7ad5264edf8a0593645a7495c3556`; loopback binding and crash-dump exclusion are the follow-up `dc12e5314369363c5dfbac845a7a7298f20ac2c8`. This journal does not approve the inherited application routes.

## 3. Execution Detail

Built and tested the web component on the pinned Nix OTP 29.0.6 installation (ERTS 17.0.6). Created two versioned 26 MiB release directories with SHA-256 manifests under ignored `var/releases/indrajaal-web/`, containing required BEAM files, public CA material, SQLite NIF and static assets. Environment files are mode 0600. No live environment or credentials were copied.

Installed the user unit from `ops/web/20260907-1309-uos-indrajaal-web@.service`. It checks its artifact manifest before launch and uses an exact OTP executable, four schedulers, four async threads, 1 GiB memory ceiling, 200% CPU quota, 256 task limit, a 3-second restart delay and a three-start/60-second budget. The action record restricts effects to the two local staging units; a fresh cooperative runtime fence was checked before start, fault injection and stop.

Started primary PID 3668604 on loopback 4103 and backup PID 3668602 on loopback 4104. Queried identity with the full Tailscale FQDN using curl `--resolve` to loopback; these ports were never publicly exposed on the Tailnet. Killed only the owned backup through systemd. It restarted as PID 3682872 with a new run ID; the primary retained its PID and run ID. Both staging units were then stopped successfully, release files retained, and the staging lease released. Port 4100/PID 3243794 remained unchanged.

## 4. Root Cause Analysis

An environment-wide OTP label did not establish the version of an already-running web VM. Observed executable paths, VM-reported OTP/ERTS, OS PID and per-start identity close that visibility gap. Staging also required an explicit loopback binding: the inherited listener bound every address.

A test command with malformed Erlang quoting generated a crash dump. An unshared candidate briefly included that file. The error was caught in the candidate diff before handoff; the dump was moved without reading or hashing it into private ignored quarantine, `.gitignore` was extended, and only the author's unshared change was rewritten. The obsolete candidate `be07bc0e` must never be integrated. No shared history was rewritten. The negative OTP 27 launch produced another quarantined crash dump when it could not load OTP 29 BEAM code.

## 5. Fix Taxonomy

Added runtime observation, explicit startup constraints, versioned release identity, loopback-by-default listening, bounded systemd supervision, manifest preflight and scoped crash-artifact exclusion. Added `SOLO5-UPDATE` and `AUTH-INGRESS` to the work-order discovery map; persisted Sa-plan state remains the authority.

## 6. Patterns & Anti-Patterns Discovered

Require actual process observations and state the boundary of declared metadata. A candidate string is not artifact attestation; a backup role label is not writer fencing or automatic failover. Check a fresh session heartbeat as well as the lease epoch: a stale heartbeat correctly refused the first cleanup attempt, after which heartbeat renewal and a fresh check allowed the authorized cleanup.

## 7. Verification Matrix

| Check | Observed result | Limit |
|---|---|---|
| Web tests on OTP 29 | 17 passed | Component workspace only |
| Bind controls | Default loopback, explicit address and invalid address rejection passed | No network-policy admission |
| Release manifest | SHA-256 check passed | Cooperative filesystem evidence |
| Two real processes | OTP 29 / ERTS 17.0.6; exact executable paths observed | Declared revision is not attested |
| Backup recovery | PID 3668602 → 3682872; restart count 1 | No failover routing tested |
| Primary continuity | PID/run ID unchanged | No client continuity load test |
| Invalid managed configuration | Exit 78 before serving | Positive startup validated separately |
| OTP 27 negative launch | Exit 1 before serving: OTP 29 code not loadable | Gleam startup guard was not reached; do not report exit 78 |
| Cleanup | Both staging units inactive; production PID 3243794 still listening | Production remains OTP 27 |

## 8. Files Modified

Runtime implementation is in `f734f8fb` and `dc12e531`. This evidence change adds `generated/20260907-1420-web-runtime-component-staging.json`, `governance/planning/20260907-1420-mirage-security-work-order.json` and this journal. Runtime manifests and receipts remain under `var/releases/indrajaal-web/`; the user service unit is installed but not enabled for boot.

## 9. Architectural Observations

Gleam owns the typed identity projection and startup decision; the small Erlang FFI reads VM/environment facts. Systemd controls the actual host process and resource budget. OTP supervision inside the application and a future fenced primary/backup dispatcher remain distinct responsibilities. The acceptance result cannot authorize a production mutation.

## 10. Remaining Gaps

P0: integrate and independently verify authenticated network ingress, including pre-read body framing bounds; the first ingress candidate `6b033f37` is not approved. P0: independently verify AGY's latest Mirage probe/receipt repair. P1: stage the exact integrated candidate and perform Claude-owned cutover with a new action, fence, rollback and client continuity checks. Sa-plan CLI leases currently use epoch wall time; the coordinator uses boot-relative time. No claim of universally monotonic leases is made.

## 11. Metrics Summary

Two real local-only staging VMs were exercised and stopped. Observed cgroup memory before cleanup was 48,730,112 bytes primary and 47,435,776 bytes backup, each with 28 tasks. These are point observations, not limits or migration savings. Seventeen component tests and three binding controls passed; one backup crash/restart was observed. No production cutover or measured RAM saving is credited.

## 12. STAMP & Constitutional Alignment

Controls address wrong-runtime deployment, unintended network exposure, runaway restart loops and mistaken admission from telemetry. Actions were confined to owned staging units with a rollback record and fresh checks. There were no native Git operations, external source mutations, drive operations or barred-engine additions. Shared main was left to Claude's serialized integration.

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Host and NTP observations stated with scope.
- [x] CHK-02-TAIL — Full FQDN links; publication pending integration.
- [x] CHK-03-FRACT — Fractal tags present.
- [x] CHK-04-KM — Work-order and evidence links supplied.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- [x] CHK-05-MUDA — Existing ecosystem only; no new inference calls.
- [x] CHK-06-GRAPH — No graph kernel or foreign graph runtime added.
- [ ] CHK-07-DRIVE — No storage-interlock test or drive operation in this task.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI modality protocol not rerun.
- [ ] CHK-09-MATH — No whole-system mathematical gate asserted.
- [ ] CHK-10-9MOD — Scoped component tests only.
- [x] CHK-11-REGR — Startup/configuration, identity and restart controls executed.

</details>
<details><summary>Domain 4 — Runtime and observability</summary>

- [x] CHK-12-GLEAM — Two actual OTP 29 web processes observed.
- [ ] CHK-13-HERMES — Hermes runtime refinement is separate.
- [ ] CHK-14-ZIGVM — Kernel/VFS laws not reverified here.
- [ ] CHK-15-MAX — Real model inference remains outside this component.
- [ ] CHK-16-OTEL — Identity and systemd observations do not prove end-to-end OTel delivery.

</details>
<details><summary>Domain 5 — Governance and JJ</summary>

- [ ] CHK-17-SOV — Integrated-candidate review and admission pending.
- [x] CHK-18-JJ — Isolated JJ candidates and fresh scoped runtime fencing.

</details>

## 13. Conclusion

Runtime preparation is implemented and exercised on actual OTP 29 primary/backup staging processes. Recovery, identity continuity, configuration rejection and cleanup have direct observations. Production remains on its original process while the exact integrated candidate and authentication repair are prepared.

**Previous:** [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · **Next:** [Mirage](http://nas-1.tail55d152.ts.net:4100/mirage)  
**UOS footer:** component evidence only; application admission is false.
