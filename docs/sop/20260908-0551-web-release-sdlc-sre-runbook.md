# 20260908-0551 — Web release SDLC and SRE standard work

#fractal-l0 #fractal-l4 #fractal-l8 #zk-adr #zero-muda #tailscale-web

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Design and laws](http://nas-1.tail55d152.ts.net:4100/docs/design/20260908-0551-release-lifecycle-denotational-specification.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260908-0551-homeostasis-release-journal.md)

## Purpose and release decision

Use a fixed candidate, a complete packaged release, actual VM observations, fresh ownership and a rehearsed rollback. A green component test is not a production admission. Production has not been updated by this procedure until a revision-bound cutover and its live postchecks are recorded.

Agents execute through Sa-plan. Manual operators inspect the same evidence and respect runtime ownership; an agent message or a model answer is not approval. Before an effect, check the task worker/attempt, unexpired task lease, session heartbeat, exact runtime lease epoch, candidate, target PID/run ID, rollback artifact and postconditions. A failed or unknown prerequisite stops that transition.

## Twelve stages: agent and manual checks

| Stage | Agent procedure | Manual procedure | Failure test / exit evidence |
|---|---|---|---|
| 1. Intake | Read Sa-plan, JJ candidate, clocks and live process identity; rank C × STPA × FMEA × dependency × impact | Compare the requested service/port with the actual OS process and endpoint | Unknown owner, unbound candidate or contradictory OTP/ERTS prevents readiness |
| 2. Design | Bind requirements to denotational laws, STPA constraints, acceptance checks and rollback | Review all four unsafe-control-action categories and blast radius | Each required design field can be removed to demonstrate rejection |
| 3. Source | Use an isolated JJ workspace; freeze exact source and dependency inputs | Check source diff and ownership; confirm no shared-mainline overwrite | Source change during build refuses release output |
| 4. Build | Native OCaml or equivalent Mojo command prepares a new directory on pinned actual OTP29 | Read build log, revision and dependency source provenance | Missing tool/runtime, nonzero compiler result and existing destination stop immediately |
| 5. Test | Run checker selftests, Gleam EUnit, 338-case differential oracle, browser and terminal checks | Inspect real/test modes, keyboard navigation, controls, disconnect/reconnect and narrow viewport | False, stale, malformed, future and foreign evidence rejected; no simulated healthy data in real mode |
| 6. Package | Recompute complete inventory and SHA-256; verify actual runtime | Inspect manifest and candidate; verify the exact package again | Altered/missing/extra files and symlinks fail; corruption tests touch only a private copy |
| 7. Staging | Start only owned isolated listeners with resource/restart/time limits; check full routing | Open all homeostasis views and compare UI with API/run identity | Inject one owned backup failure; primary must preserve its run ID; exercise A/B/A restoration |
| 8. Authorize | Recheck task and runtime fences and typed action | Review concrete candidate, target, effect, rollback and postcheck | Stale epoch, expired heartbeat, unavailable rollback or wrong candidate stops effect |
| 9. Deploy | A separate authorized executor replaces only the named target; no migration on normal boot | Observe service/PID/port change and readiness; inspect bounded startup failure | Startup or readiness failure selects the tested rollback; no blind retry loop |
| 10. Observe | Compare actual release identity, route behavior, fresh measurements and logs | Keep a real-data view open; confirm updates and visible stale/disconnected state | HTTP200 alone is insufficient; mismatched candidate, blank payload or stale frame fails |
| 11. Recover | Restore an explicitly bound previous artifact and verify its identity | Check restored behavior and client impact, then record residuals | Backup process restart and artifact rollback are different tests; no automatic failover claim |
| 12. Close | Retain receipts, source pointers and 13-section journal; complete only scoped Sa-plan task | Accept or reject user-visible behavior; review unresolved risks | Missing review, journal, evidence or remaining-gap record prevents closure |

The packet checker tests the structure of a complete 12-stage evidence packet. It does not manufacture missing production receipts or authenticate submitted evidence. Global deployment authorization remains a separate check.

## Commands — no new Bash scripts

For the configurable fifty-focus run, exact JSON guard, native recording command and stronger receipt checker, apply the [fifty-cycle assurance extension](http://nas-1.tail55d152.ts.net:4100/docs/sop/20260908-0906-fifty-cycle-assurance-sop.md). Its freshness and dependency restrictions supersede an assumption that an offline Nix command cannot download.

Package provisioning follows [SC-RELEASE-ASSURANCE-001](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0551-release-assurance-sdlc-sre-sop.md). The repository carries ops/release/flake.nix and flake.lock. Provision once with Determinate Nix before running browser checks:

```text
nix build --offline path:./ops/release#default --out-link /home/an/NAS-setup/uos/var/releases/indrajaal-web/toolchain-20260908-0551
```

The browser command uses that profile's compiler and development libraries. Missing dependencies fail rather than triggering an implicit installer.

Run from the isolated review workspace recorded in the journal. Both interfaces accept the same command and arguments:

```text
ocaml tools/release_process.ml COMMAND [ARGS]
/home/an/.pixi/bin/pixi run --no-install --frozen --manifest-path /home/an/NAS-setup/uos/services/inference/max/pixi.toml mojo tools/release_process.mojo COMMAND [ARGS]
```

The second command reuses the already-installed Mojo/Python environment without updating its environment or lock. Any future Python installation for this work MUST use devenv or Determinate Nix. The Mojo frontend uses only Python's existing standard-library os.execv, with a list of arguments and no shell evaluation. No pip installation or new Pixi Python environment is authorized by this SOP.

| Command | Arguments | Meaning |
|---|---|---|
| selftest | none | Process-boundary and all stage-receipt negative tests |
| model-selftest | none | Finite prefix model check |
| model-table | none | Deterministic 338-row transition observation table |
| runtime-check | SOURCE_ROOT | Compile/run actual VM observer on installed OTP27 and OTP29; reject spoofed labels |
| unit | SOURCE_ROOT | Fresh Gleam compilation, EUnit and three-language transition parity |
| browser | SOURCE_ROOT RELEASE_DIR PRIVATE_PORT | Compile and run the OCaml browser suite, with candidate smoke checks before/after |
| build | NEW_ABSOLUTE_RELEASE_DIR | Prepare a new release; refuse overwrite or changed source |
| verify | RELEASE_DIR | Full inventory/byte and actual OTP check |
| package-faults | RELEASE_DIR | Corrupt a private copied package; original preserved |
| parity | SOURCE_ROOT RELEASE_DIR TAILSCALE_BASE | Compare OCaml/Mojo exit codes and outputs on listed positive and negative cases |
| smoke | TAILSCALE_BASE EXPECTED_REVISION | Check actual identity and eight complete web routes |
| packet | JSON EXPECTED_REVISION | Validate complete ordered stage-evidence structure |
| web | RELEASE_DIR PORT TAILSCALE_FQDN | Manual full web foreground process until stopped; no implicit deployment authority |
| tui | RELEASE_DIR real\|test SCENARIO CYCLE | One-shot native terminal view; cycle 1..30 |

Scenarios: nominal, disturbance, recovery, unavailable. Real TUI mode observes the TUI process's own VM; it is not a remote view of production's VM. The browser terminal page observes the serving web process. Neither control surface gains execution permission.

Examples:

```text
ocaml tools/release_process.ml selftest
ocaml tools/release_process.ml unit /home/an/NAS-setup/uos/.uos-workspaces/codex-homeostasis-release-20260908-0551
ocaml tools/release_process.ml verify /home/an/NAS-setup/uos/var/releases/indrajaal-web/homeostasis-native-v5-20260908-0551
ocaml tools/release_process.ml tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/homeostasis-native-v5-20260908-0551 test disturbance 3
ocaml tools/release_process.ml tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/homeostasis-native-v5-20260908-0551 real nominal 1
```

For a manual web instance, first verify that the chosen private port is unused and that no other session owns it. Then run:

```text
ocaml tools/release_process.ml web RELEASE_DIR 59457 nas-1.tail55d152.ts.net
```

The foreground command ends when the operator stops it. The launcher requires the Tailscale FQDN; private socket binding is handled internally. Private smoke tests retain the full Tailscale FQDN and explicitly resolve private ports to loopback; they do not prove remote Tailnet reachability. A remote browser needs an operator-established tunnel or a separately authorized Tailnet bind. Production is [the port-4100 homeostasis page](http://nas-1.tail55d152.ts.net:4100/homeostasis/evolution); do not confuse that running deployment with a staged instance.

## Manual GUI/TUI acceptance card

1. Confirm the release candidate, actual OTP/ERTS, PID, run ID, role and start time at [runtime identity](http://nas-1.tail55d152.ts.net:4100/api/v1/runtime/identity).
2. Open [evolution](http://nas-1.tail55d152.ts.net:4100/homeostasis/evolution), [components](http://nas-1.tail55d152.ts.net:4100/homeostasis/components), and [terminal projection](http://nas-1.tail55d152.ts.net:4100/homeostasis/terminal). Use the staged equivalents when testing staging.
3. Select test/disturbance and verify simulated labels and changing values. Return to real and ensure simulation values disappear.
4. Leave the view open and confirm the event/frame counter and observation timestamp advance. Disconnect the stream and verify stale/unknown indicators replace old measurements.
5. Tab through the mode selectors, sliders, checklist and review control. Verify the accessible slider output changes; real execution must remain denied without separate authority.
6. Repeat at 320, 768 and 1280 pixels. Check clipping, horizontal overflow and browser errors.
7. Run both native TUI modes. Confirm readable bounded output and data-source labeling.
8. Record the human observer, exact candidate, time and result. Automated browser checks cannot claim human acceptance.

## Phoenix/Elixir practices adapted to UOS

- Separate compiled releases from runtime configuration and secrets. UOS uses packaged BEAM code, explicit startup configuration and a manifest. The deployment approach is informed by the [Phoenix deployment guide](https://phoenix.hexdocs.pm/deployment.html).
- Keep migrations as explicit release operations with their own rollback constraints. This follows the separation available in [Phoenix release tasks](https://github.com/phoenixframework/phoenix/blob/main/guides/deployment/releases.md); this web release performs no live schema migration.
- Test initial HTML separately from the connected update lifecycle, then exercise actual rendered controls. UOS applies that pattern to SSR plus SSE and browser interaction, informed by [Phoenix LiveView testing](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveViewTest.html).
- Distinguish supervision/restart from traffic failover, and liveness from readiness. Test shutdown, client continuity and telemetry delivery as separate SRE obligations. These are UOS design choices requiring local evidence, not capabilities obtained merely by copying Phoenix terminology.
- Keep deterministic unit/model tests cheap; use integration tests for transport/storage and bounded browser tests for rendered behavior. Never run fixture mutation against canonical live stores.

OCaml is the preferred implementation language for the operational core because the installed ecosystem already supports its I/O, JSON, cryptography and test tooling. Mojo provides an equivalent command surface through the same core and an independent computational oracle. Functional equivalence is checked over normalized observations; fresh timestamps, PIDs and temporary paths may legitimately differ. Two independent deployment engines would add divergence risk without useful benefit here.

## Stop conditions and rollback

Do not replace port4100 until the actual production source/rollback binding, required security boundary, exact runtime ownership and target-specific postchecks are available. The inherited process's declared revision is empty; preserving a development build directory does not prove that it is the bytecode already loaded by that process.

Staging fault tests operate only on explicitly named units and ports. Keep fallback artifacts. If a staging attempt fails, stop only the owned staging unit and inspect its bounded logs. Never kill all BEAM processes, delete shared state, regenerate a shared journal or rewrite another session's source.

The final bounded canary uses Restart=no with RuntimeMaxSec=600. Restart=on-failure would restart a service after RuntimeMaxSec expires; that is not an overall lifetime bound. A deliberate restart drill has its own retry budget and explicit cleanup. Transient systemd units may disappear after stopping: restoration recreates the saved launch definition and then verifies the restored candidate. Probe readiness after actual startup; an immediate pre-start connection failure is a failure receipt, not success.

Apply the [17-aspect and fractal RCA/Jidoka review](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-release-17-aspect-and-source-review.md) at each gate. The matrix distinguishes scoped observations from unverified whole-system requirements and records the C3I/Indrajaal source review.

A future production executor must test stale-lease rejection at the effect boundary, supervised startup, draining/in-flight request behavior, failed readiness, restoration of the exact approved prior artifact, and final live identity. Until those target-specific tests pass, record deploy as BLOCKED or UNRUN rather than filling a successful stage packet.


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
