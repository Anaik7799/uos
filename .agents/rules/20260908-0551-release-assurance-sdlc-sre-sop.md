# 20260908-0551 — SDLC/SRE release assurance and package provisioning SOP

#fractal-l0 #fractal-l4 #fractal-l8 #zk-adr #zero-muda #tailscale-web

Contract: SC-RELEASE-ASSURANCE-001. Basis: explicit operator directives in this side conversation. This candidate standard becomes repository-wide through normal reviewed integration; its presence is not production admission.

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Procedures](http://nas-1.tail55d152.ts.net:4100/docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md) · [17-aspect/RCA review](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-release-17-aspect-and-source-review.md)

1. All SDLC/SRE work MUST use canonical Sa-plan tasks, bounded scope, explicit owners, and fresh effect-time fencing. Rank eligible work by criticality × STPA × FMEA × dependency × impact. Hard safety/dependency blockers take precedence over ranking.
2. New package provisioning MUST use Determinate Nix or devenv with repository-contained pinned inputs. New Python installations and libraries MUST follow that route too. No pip, apt, conda, or Pixi installation step substitutes for it. Existing environments may execute without installation; the current Mojo invocation uses --no-install --frozen. New shell/Bash automation is prohibited for this release process.
3. Operational tools MUST expose equivalent OCaml and Mojo commands, argument validation, outcome semantics and bounds. A shared operational core is acceptable; independent finite models must remain independent. Dynamic PIDs, times, and private paths are compared by their contracts, not byte identity.
4. Requirements MUST have a denotational meaning, explicit typed intent, state-machine transition, algebraic law, failure case and test/evidence pointer. UOS FPP projections and atlas declarations MUST NOT claim official F Prime certification or mathematical verification without current verifier receipts.
5. Release gates MUST cover intake, design, source, build, test, package, staging, authorize, deploy, observe, recover and close. Every applicable gate needs agent automation and a documented manual procedure. Human acceptance remains UNRUN until a human actually performs it.
6. Build and tests MUST bind to a fixed source candidate and recorded dependency/toolchain inputs. Release inventories MUST reject corruption, unexpected/missing files and unsupported entries. Code and artifact identity MUST be rechecked at startup and after observation.
7. Runtime health MUST distinguish declared configuration from observed OTP, ERTS, PID, run ID, timestamps, counters and readiness. Missing, contradictory, stale or simulated evidence cannot be reported as live healthy status or admission.
8. GUI/TUI/API/SSE checks MUST test shared data meanings, test/real separation, rendered content, current candidate, accessible interaction, visible update/staleness, errors and disconnects. HTTP200, static badges, source inventory and recorded historical clips alone do not establish current functionality.
9. All 17 canonical aspects MUST be considered explicitly. Applicable UNKNOWN/UNRUN/FAIL obligations prevent a full-compliance claim. A component test count cannot compensate for a missing security, runtime, formal, governance or recovery requirement.
10. A failed prerequisite MUST stop the affected transition (Jidoka). Fractal RCA MUST identify symptom, cause hypothesis, evidence, constraint, owner, containment, falsifier and recovery at affected layers. No unbounded restart loops or global process kills. Model outputs advise; typed external authorization owns effects.
11. Production replacement MUST have an exact target, current ownership, tested fallback artifact, bounded startup/drain/recovery and actual post-change verification. Primary/backup deployment does not imply verified traffic failover.
12. Closure MUST retain the 13-section journal, machine-readable receipt, honest remaining gaps, manual acceptance status and canonical task outcome. Artifacts must be published/indexed through their own authorized integration; do not claim workspace-only documents are already live.
13. All operational host names, HTTP/browser URLs and remote targets MUST use the canonical Tailscale FQDN, including private staging. Private staging uses declared local resolver mapping without exposing a listener publicly. Socket addresses remain transport implementation details. Browser application requests outside the FQDN are refused. Once packages are cached, use offline Nix provisioning; an uncached dependency requires an operator-supplied Tailnet package mirror under this rule, not silent public-registry access.

14. Every release decision MUST retain a reviewable task summary with context, goals, evidence, alternatives, selected action, uncertainties, falsifier and next gate. Do not demand private model reasoning. Forecasts MUST identify candidate/source, horizon, assumptions, resolution criterion and calibration status. Demonstration values and self-reported confidence are not measured probability or authority. STM/Rete/formal-tool names cannot substitute for invocation receipts. Apply the [decision and forecast standard work](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-release-decision-and-forecast-review.md).

## Pinned package commands

From the reviewed repository workspace:

```text
nix build --offline path:./ops/release#default --out-link /home/an/NAS-setup/uos/var/releases/indrajaal-web/toolchain-20260908-0551
nix develop --offline path:./ops/release
```

The checked-in flake and lock pin nixpkgs revision c25784012c9982bca5b3e0de87e90bbdac8927d3. The provisioned profile contains compiler/linker tooling, curl and development libraries, pkg-config and zlib. OCaml, Mojo, BEAM, Chrome and the Playwright driver are existing explicitly required tools; this profile does not pretend to install them or Python. Extend the pinned definition when a new dependency is needed, then verify its effects and record its store path/digest.

The native browser command resolves the provisioned profile to the Nix store and uses its compiler and libraries. It does not install packages implicitly. UOS_RELEASE_TOOLCHAIN may select another explicitly provisioned Nix store profile.


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
