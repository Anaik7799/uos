# Manual GUI and TUI testing guide

Generated: 2026-09-08 12:08:34 UTC. Filename follows the required YYYYMMDD-HHSS convention (hour and seconds).
Tags: #fractal-l0 #fractal-l2 #fractal-l5 #fractal-l8 #zero-muda #tailscale-web #checklist-nav

The updated **homeostasis test instance is running**. Open the [GUI](http://nas-1.tail55d152.ts.net:59463/homeostasis/evolution) from a device connected to the Tailnet. No browser DNS override is needed.

This package combines main `231ba3dbf23080d90020a06ce4ce331824e9dac1` with reviewed UI work `6d15a6d32f798116634a8eb8760e775eb409133c` and the restricted manual-test listener. Its executable candidate is **517252df824c487ee80e61dfb4dec0fc139ec086**. Main still points to the observed base; production on port 4100 was not changed. Later documentation commits do not change the running package.

## 1. Open the right instance

| Surface | Link | Expected result |
|---|---|---|
| GUI overview | [Homeostasis evolution](http://nas-1.tail55d152.ts.net:59463/homeostasis/evolution) | Real mode; observed local BEAM counters |
| Component views | [Components](http://nas-1.tail55d152.ts.net:59463/homeostasis/components) | Expand Component views and select a panel |
| Terminal in browser | [Terminal view](http://nas-1.tail55d152.ts.net:59463/homeostasis/terminal) | Visible plain-text panel with live updates |
| Same server, raw terminal text | [Terminal API](http://nas-1.tail55d152.ts.net:59463/api/v1/homeostasis/terminal) | One plain-text snapshot |
| Data API | [Homeostasis JSON](http://nas-1.tail55d152.ts.net:59463/api/v1/homeostasis) | `observed`, real counters; unsupported health unknown |
| Runtime identity | [Identity JSON](http://nas-1.tail55d152.ts.net:59463/api/v1/runtime/identity) | Values listed below |
| Simulation | [Disturbance, cycle 3](http://nas-1.tail55d152.ts.net:59463/homeostasis/evolution?mode=test&scenario=disturbance&cycle=3) | Clearly marked SIMULATED |
| Missing source | [Unavailable fixture](http://nas-1.tail55d152.ts.net:59463/homeostasis/evolution?mode=test&scenario=unavailable&cycle=1) | UNAVAILABLE; no invented healthy values |

The test server deliberately serves homeostasis and runtime identity only. Cockpit in its navigation returns the homeostasis overview. File browsing, wiki, planning, MCP and operational endpoints return 404 on this port; write methods return 405.

Runtime identity at verification:
- OTP `29`, ERTS `17.0.6`, `runtime_ready:true`, `identity_consistent:true`.
- Candidate `517252df824c487ee80e61dfb4dec0fc139ec086`.
- Instance `manual-test-59463`, PID `2599189`, run ID `2599189-1788868993762662`.
- `application_admitted:false` and `managed:false` are intentional; a test listener does not establish application admission.

The service started **2026-09-08 12:03:12 UTC / 14:03:12 Europe/Stockholm**. It automatically stops after four hours, approximately **16:03:12 UTC / 18:03:12 Stockholm**, and can stop sooner if it reaches its resource limits. Limits: 1 GiB, two CPU equivalents, 128 tasks, no automatic restart.

## 2. Manual GUI acceptance pass — about 10 minutes

Keep the tab visible while checking update timing. A source timestamp is UTC microseconds; test model time is a separate simulation coordinate.

| Step | Action | Pass condition |
|---|---|---|
| G01 — identity | Open Identity JSON before testing. | Candidate, instance and actual OTP/ERTS match above. A different run ID requires a fresh test receipt. |
| G02 — initial render | Open the overview. | Heading, navigation, controls and panels render without a blank page or script error. |
| G03 — real data | Select Real data and Apply data mode. | OBSERVED; source identifies local BEAM counters. Process count, VM memory, schedulers, queue and uptime are present. CPU percentage, host-memory percentage, PID health and peer quorum remain UNKNOWN. |
| G04 — live updates | Note Received frames and Source UTC microseconds; wait at least 30 seconds. | Both advance; stream remains CONNECTED / OBSERVED. Values need not all change when the measured system is steady. Automated run observed source advancement of at least 30,000,000 microseconds and at least 10 frames. |
| G05 — simulation | Select Test data, disturbance, cycle 3, then Apply. | SIMULATED; initial fixture has CPU 98.0, memory 95.0 and phase Intervention. The stream advances model cycles 1–30, then wraps; it is not evidence of executing 30 real operational changes. |
| G06 — recovery | Select test/recovery/cycle 10 and Apply. | SIMULATED; initial sample has health 1.0, phase Equilibrium and energy 0.0. These model outputs are not production health claims. |
| G07 — missing source | Open the unavailable-fixture link. | UNAVAILABLE and unknown measurements. The JSON API for this fixture returns 503, which is expected. |
| G08 — data separation | Return to Real data. | Simulated physiology and model values clear to UNKNOWN; only supported observed VM counters remain. |
| G09 — controls | Move CPU and memory threshold sliders. Request equilibrium review in test mode, then real mode. | Slider output changes. Test mode returns a simulated preview, with `executed:false`; real mode denies execution with HTTP 403. No runtime configuration changes. |
| G10 — navigation | Expand Component views and visit each of the ten entries: provenance, controls, pid, phase, physiology, runtime, pareto, quorum, stream, checklist. Then open Terminal view. | Selected panel is visible; other component panels are hidden. All clickable GUI links keep port 59463 and preserve the data selection. Terminal view shows its terminal panel. |
| G11 — keyboard/layout | Use Tab, Shift+Tab, Enter and arrow keys. Open the checklist with Enter. Resize to 320, 768 and 1280 pixels. | Visible focus, operable controls, readable content and no whole-page horizontal overflow. Individual tables may scroll. |
| G12 — interrupted stream | In browser developer tools, switch this browser session Offline while the page is visible. Wait 6–10 seconds, then return Online. | DISCONNECTED or STALE; old measurements clear rather than remaining presented as current. On reconnect, fresh frames resume. If the browser does not interrupt an existing stream, record the fault test as BLOCKED rather than PASS. |
| G13 — reconnect/exit | Keep the stream open for over two minutes; navigate away and return. | A bounded SSE connection may reconnect after 120 samples; fresh data resumes. Leaving the page closes its subscription. |
| G14 — errors/evidence | Check browser Console and Network. Save a screenshot and a 30-second clip of the visible update test. | No unexpected JavaScript error or failed request. Expected 403/404/405/503 responses above are identified separately. Record the candidate and observed UTC with the evidence. |

The 18-item UI checklist describes evidence obligations. Its UNRUN labels are deliberate where application admission receipts have not been attached; do not turn them green based only on this manual pass.

## 3. Test terminal output manually

From another Tailnet computer, connect to NAS-1:

```text
ssh an@nas-1.tail55d152.ts.net
```

First verify the immutable package. Run these commands on NAS-1; no installation or shell script is needed:

```text
cd /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200
/home/an/dev/ver/zigvm/_opam/bin/ocaml release_process.ml verify /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200
/home/an/dev/ver/zigvm/_opam/bin/ocaml release_process.ml tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 real nominal 1
/home/an/dev/ver/zigvm/_opam/bin/ocaml release_process.ml tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 test disturbance 3
/home/an/dev/ver/zigvm/_opam/bin/ocaml release_process.ml tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 test recovery 10
/home/an/dev/ver/zigvm/_opam/bin/ocaml release_process.ml tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 test unavailable 1
```

This native TUI entrypoint is a **one-shot text view**, not a full-screen interactive application. It prints a snapshot and exits without changing terminal modes. Real mode measures its own short-lived BEAM VM, so its uptime and process count need not match the long-running web server.

| Mode | Expected terminal result |
|---|---|
| real / nominal / 1 | OBSERVED, real VM counters, unsupported health UNKNOWN, authority NONE |
| test / disturbance / 3 | SIMULATED, phase Intervention, health 0.35, CPU 98.0 |
| test / recovery / 10 | SIMULATED, phase Equilibrium, health 1.0, energy 0.0 |
| test / unavailable / 1 | UNAVAILABLE, source time and measurements UNKNOWN |

Repeat a fixture command: its output should be identical. Repeat real mode: timestamps change; equality of independently sampled counters is not required. Invalid mode, scenario or cycle outside 1–30 must exit nonzero.

To inspect the **same running VM as the GUI** from any Tailnet terminal:

```text
curl --fail --silent --show-error --max-time 10 http://nas-1.tail55d152.ts.net:59463/api/v1/homeostasis/terminal
curl --fail --silent --show-error --max-time 10 http://nas-1.tail55d152.ts.net:59463/api/v1/runtime/identity
```

The plain-text projection includes a legacy port-4100 footer reference. It does not select its telemetry source. Use the explicit port-59463 URLs above for this test instance. Terminal source descriptions may be clipped at the renderer's 120-column bound.

The existing Mojo entrypoint forwards to the same OCaml operational core. This exact simulation invocation was compared byte-for-byte with OCaml:

```text
/home/an/.pixi/bin/pixi run --no-install --frozen --manifest-path /home/an/NAS-setup/uos/services/inference/max/pixi.toml mojo /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200/release_process.mojo tui /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 test disturbance 3
```

This is shared-core CLI parity, not a claim of two independent implementations. No dependency installation was performed. Any missing dependency must be supplied through the approved Determinate Nix/devenv process.

## 4. Check the service or start a later manual session

On NAS-1:

```text
systemctl --user show uos-manual-ui-59463.service --property=ActiveState,SubState,MainPID,InvocationID,ActiveEnterTimestamp,RuntimeMaxUSec
journalctl --user -u uos-manual-ui-59463.service -n 60 --no-pager
```

This run's InvocationID is `ba557de3ef1e44e6a272142baea0056a`. Check it before stopping the unit. To stop this exact test run, the operator can use:

```text
systemctl --user stop uos-manual-ui-59463.service
```

After expiry or an intentional stop, first verify the unit is inactive and port 59463 is free. Coordinate a new Sa-plan task and runtime lease before an agent starts another session. The human operator can run a foreground test listener from the verified package:

```text
/home/an/dev/ver/zigvm/_opam/bin/ocaml /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200/release_process.ml manual-web /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 59463 nas-1.tail55d152.ts.net
```

This foreground command runs until Ctrl+C and does not inherit the original systemd four-hour/resource limits. Keep it attended. Do not launch it over an existing listener or redirect production port 4100. A new run has a new PID/run ID; recheck identity and repeat acceptance.

If the GUI cannot be reached: check Tailnet connectivity, exact hostname/port, service status and expiry, then the identity endpoint. Do not replace the URL with localhost or a raw IP. A refused connection after expiry is not a rendering regression.

## 5. Agent-assisted repeat and evidence

The task used Sa-plan `uos/manual-ui/20260908-1150` / `PREPARE`, worker `codex-manual-ui`, and its isolated JJ workspace. Future agent work must obtain current ownership; this guide is not an execution lease.

The native commands that produced the scoped results are:

```text
/home/an/dev/ver/zigvm/_opam/bin/ocaml /home/an/NAS-setup/uos/.uos-workspaces/codex-manual-ui-20260908-1150/tools/release_process.ml unit /home/an/NAS-setup/uos/.uos-workspaces/codex-manual-ui-20260908-1150
/home/an/dev/ver/zigvm/_opam/bin/ocaml /home/an/NAS-setup/uos/.uos-workspaces/codex-manual-ui-20260908-1150/tools/release_process.ml smoke-manual http://nas-1.tail55d152.ts.net:59463 517252df824c487ee80e61dfb4dec0fc139ec086
/home/an/dev/ver/zigvm/_opam/bin/ocaml /home/an/NAS-setup/uos/.uos-workspaces/codex-manual-ui-20260908-1150/tools/release_process.ml browser-manual /home/an/NAS-setup/uos/.uos-workspaces/codex-manual-ui-20260908-1150 /home/an/NAS-setup/uos/var/releases/indrajaal-web/manual-ui-20260908-1200 59463
```

Fresh evidence: **127 scoped tests**, **338 transition-parity cases**, **62 browser checks**, a **16-case manual HTTP smoke**, four native TUI modes, Mojo/OCaml fixture equality and successful access from VM-1. Browser widths were 320/768/1280; the live-update observation lasted at least 30 seconds. These results cover the homeostasis test surface. They do not establish whole-monorepo, all-screen, failover, production, 17-aspect or formal admission.

Use one row per human test:

| Test ID | UTC | Candidate + run ID | URL / command | Expected | Actual | Result | Evidence |
|---|---|---|---|---|---|---|---|
| G04 or TUI scenario | Fill from observed host time | Copy identity | Exact FQDN/command | Expected behavior | Observed behavior | PASS / FAIL / BLOCKED | Screenshot, clip or text receipt |

Retained [machine receipt](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-manual-ui-20260908-1150/tests/evidence/20260908-1234-manual-ui-testing/receipt.json), [browser checks](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-manual-ui-20260908-1150/tests/evidence/20260908-1234-manual-ui-testing/browser.txt), [unit log](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-manual-ui-20260908-1150/tests/evidence/20260908-1234-manual-ui-testing/unit.txt) and [journal](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-manual-ui-20260908-1150/docs/journal/20260908-1234-manual-ui-testing-journal.md) support the automated observations. The captured PNG names contain an older fixed prefix from the test harness; their actual run provenance is the receipt, not that filename. No new 30-second video recording is claimed.

## 6. Verification obligations — 5 domains, 18 checkpoints

<details>
<summary>Expand the 18 evidence obligations; scoped verification is not application admission.</summary>

| Domain | Checkpoints and current scope |
|---|---|
| Metadata and navigation | 01 observed UTC and prefix recorded; 02 Tailnet access verified locally and from VM-1; 03 fractal tags present; 04 guide, journal and evidence linked |
| Purity and storage safety | 05 no new barred dependency or package installation in this change; 06 Gleam listener/OCaml tooling within existing boundaries; 07 no storage or production mutation; global storage safety UNRUN |
| Tests and mathematics | 08 127 scoped tests, broader C1–C8 completeness UNRUN; 09 338 finite parity cases, universal proof UNRUN; 10 automated browser plus pending human acceptance; 11 62 browser checks, complete all-screen regression UNRUN |
| Control and observability | 12 actual OTP29/ERTS17.0.6 observed; 13 OCaml package/HTTP checks, new Gospel proof UNRUN; 14 ZigVM runtime unaffected and UNRUN here; 15 inference unaffected and UNRUN here; 16 candidate/run/source/frame evidence linked |
| Governance and JJ | 17 own task/lease and report; independent peer admission UNRUN; 18 isolated JJ candidate and immutable package, main/production unchanged |

</details>

Production port 4100 separately returned readiness 503 with an incoherent OTP29/ERTS15 pair during this check. A previous broad suite recorded 12 NIF ABI failures. This test package does not repair or clear those integration blockers.

