# 20261105-1745 — Canonical source for the out-of-BEAM guardian units

These files are the **reviewable source of truth** for the external guardians
installed under `~/.config/systemd/user/`. They were previously present only in
the home directory: untracked by Jujutsu, outside the KM corpus, and therefore
invisible to an independent reviewer. Codex attempted
`uos://km/ops/systemd/user/uos-web-watchdog.timer` during review and received
`RESOURCE_NOT_FOUND`; this directory closes that gap.

| File | Installed path | Purpose |
|---|---|---|
| `uos-web-watchdog.service` | `~/.config/systemd/user/` | Runs `tools/uos_web_watchdog.exe` as a oneshot, out-of-BEAM |
| `uos-web-watchdog.timer` | `~/.config/systemd/user/` | 60 s cadence; `WantedBy=timers.target` |
| `c3i-gleam-server.service.d/10-restart-always.conf` | `~/.config/systemd/user/c3i-gleam-server.service.d/` | `Restart=always` + widened start limit |

## Install

```
cp -r ops/systemd/user/. ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now uos-web-watchdog.timer
```

## Invariant — do not break this

`uos-web-watchdog.service` must **never** gain `PartOf=`, `BindsTo=` or
`Requires=` on `c3i.target` or `c3i-gleam-server.service`. The whole point is
that it survives the fate domain it protects (`THM_EXT_04` in
`formal/lean/UosCoreEvoUnifiedDigitalTwin.lean`). Coupling it re-creates the
co-residency defect that left the plane dark for 41 h on 2026-11-03/05.

These copies are configuration, not admission. EV ceiling 93.
