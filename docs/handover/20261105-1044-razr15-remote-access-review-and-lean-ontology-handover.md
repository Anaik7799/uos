# 20261105-1044 — Handover: razr15-1 remote-access doc review + Lean access ontology

#fractal-l1 #fractal-l4 #fractal-l6 #fractal-l7 #zk-adr #zero-muda #tailscale-web

- **Observed host UTC**: `2026-11-05T10:19:44Z` (nas-1 clock, read immediately before writing)
- **Author session**: Claude Opus 5, workspace `/home/an/NAS-setup/uos`
- **Outgoing to**: Claude (continuation session)
- **Status**: review DELIVERED (with one finding now contradicted — see §3); Lean module NOT yet written
- **Links**: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

---

## 1. Operator request (verbatim, in order)

1. `review the latest remote access doc on razr15-1 in folder c:/dev/docs/journal`
2. `review the latest remote access doc on razr15-1 in folder c:/dev/docs/journal. create or update the lean based code that has razr15-1 details, ontology and acccess details`
3. `save state and handover to claude`

Request 1 is **done** (review delivered as text). Request 2's Lean half is **not started** — no file
written, no edit made. Request 3 is this document.

## 2. Review target

`razr15-1:C:\dev\docs\journal\20261105-0615-wsl2-ssh-remote-access-framework.md`
(18770 bytes, mtime 2026-11-05 09:11, status line `COMPLETED & VERIFIED`, 8 sections).
Reached over the WSL2 path the doc itself establishes: `ssh -p 2222 an@100.114.9.28`.
Windows OpenSSH on `:22` rejects nas-1's key, so `C:\dev\...` is read via `/mnt/c/dev/...` from inside WSL2.
It is the only 2026-11-05 file in that folder; the other six date from 2026-03-23/24, so "latest"
and "latest remote access" resolve to the same file.

## 3. CORRECTION PENDING — deliver this to the operator

The review as delivered stated the network guard was `enabled` + `active`, and raised its
`Type=oneshot` boot-only behaviour as design finding #4. A **clean re-probe at ~10:19Z contradicts
that**: the unit and its script do not exist on the host at all.

```text
/etc/systemd/system/wsl-ssh-network-guard.service   -> No such file or directory
/usr/local/sbin/wsl-ssh-network-guard.sh            -> No such file or directory
systemctl is-enabled wsl-ssh-network-guard.service  -> not-found
systemctl is-active  wsl-ssh-network-guard.service  -> inactive
systemctl list-unit-files | grep -i wsl             -> wsl-pro.service only
```

So §6.1 of the doc inventories two artifacts that are **absent**, and `eth0` currently holds
`172.17.154.247/20` without any guard enforcing it. The finding is therefore stronger, not weaker:
the hardcoded-IP dependency has **no** enforcement mechanism at all, not merely a boot-only one.

Two further divergences from the earlier reading, both from the clean probe:

| Item | Earlier in session | Clean re-probe 10:19Z |
|---|---|---|
| keepalive process | `587 wsl-ssh-keepalive infinity` | `24087 razr15-keepalive infinity` |
| `~/.ssh/authorized_keys` | 6 lines / 5 comments | **5 lines** / 5 comments |

The earlier `pgrep -af` was unanchored and is known in this workspace to match the probing shell
itself (see memory `pgrep-pattern-kills-own-shell`), so the `wsl-ssh-keepalive` / PID 587 reading is
**not trustworthy**. The anchored `ps -eo pid,args | grep -E '^[ ]*[0-9]+ razr15-keepalive'` form is.
Do not cite PID 587, the 6-line key count, or the guard unit as verified.

**Unresolved question for the operator**: were the guard unit and script ever installed (making the
doc aspirational on that point), or installed and later removed? Uptime went 3h02m -> 5h05m across
the two observations with no reboot, so nothing was lost to a restart.

## 4. Live facts that DID verify (bind these; they are fresh at 10:19Z)

```text
hostname                RAZR15
identity                an, uid 1000, gid 1000
kernel                  6.18.33.2-microsoft-standard-WSL2
distro                  Ubuntu 26.04.1 LTS
eth0                    172.17.154.247/20   (= Windows portproxy target)
listeners               0.0.0.0:2222  [::]:2222
systemd units           ssh.service active, ssh.socket active
uptime                  up 5 hours, 5 minutes
keepalive               pid 24087, argv[0] "razr15-keepalive", arg "infinity"
sshd drop-in effective  Port 2222 / ListenAddress 0.0.0.0 / ListenAddress :: /
                        PubkeyAuthentication yes / PasswordAuthentication no /
                        KbdInteractiveAuthentication no / GatewayPorts no
authorized_keys         5 lines: ed25519 an@vm-1, ed25519 abhij@RAZR15,
                        ed25519 an@nas-1, rsa root@nuc-1, rsa abhij@RAZR15
                        (4 distinct identities; abhij@RAZR15 twice = ed25519 + rsa)
```

`C:\Users\abhij\.wslconfig` (read via `/mnt/c/`): `memory=32GB`, `processors=12`, `swap=8GB`,
`localhostForwarding=true`, `nestedVirtualization=true`, `guiApplications=false`, `gpuSupport=true`,
`vmIdleTimeout=-1`; `[experimental] autoMemoryReclaim=gradual`, `sparseVhd=true`, `autoProxy=false`.
No `networkingMode=mirrored` line — consistent with the doc's §3.2 resolution.

`/etc/wsl.conf` inside WSL2: `[boot] systemd=true`; `[network] generateResolvConf=false`;
`[user] default=an`; `[automount] enabled=true, options="metadata,umask=22,fmask=11", mountFsTab=true`;
`[interop] enabled=true, appendWindowsPath=true`.

## 5. Review findings as delivered (ranked, with §3 applied)

1. **§5.1 advertises an endpoint that does not work, and §7 never tests it.** `razr15-win`
   (`100.114.9.28:22`, user `abhij`, "Public Key") fails from nas-1 with
   `Permission denied (publickey,password,keyboard-interactive)`. Cause: `abhij` is a Windows
   administrator, so Windows OpenSSH reads `C:\ProgramData\ssh\administrators_authorized_keys` and
   ignores `~/.ssh/authorized_keys`. §6.1.4 inventories only the WSL2-side keys. The 12-row matrix
   covers `:2222` exhaustively and gives `:22` **zero** coverage — the one untested endpoint is the
   broken one. Fix or strike the row.
2. **Security asymmetry undisclosed.** §3.3 frames password exposure as resolved; that holds only
   for `:2222`. Windows `:22` on the same Tailscale IP still offers `password,keyboard-interactive`
   (confirmed with `-o PreferredAuthentications=none`). A reader of §3.3 will conclude password auth
   is gone from the node.
3. **The watchdog probe can read healthy while the path is dead.** §3.1's watchdog polls
   `127.0.0.1:2222`, which is the **portproxy listener owned by `svchost.exe`** — it accepts TCP
   whether or not a WSL2 backend exists. That is precisely the Root-Cause-2 symptom the same doc
   documents ("accepts incoming connections and times out trying to forward them"). Observed
   empirically earlier today, before 09:11: `:2222` completed the handshake then died with
   `Connection timed out during banner exchange`. The probe must require the `SSH-2.0-` banner.
4. **Hardcoded IP with no enforcement** (strengthened per §3). The chain depends on `eth0` being
   exactly `172.17.154.247` because the portproxy hardcodes it; Windows reassigns the WSL Hyper-V
   switch subnet across host reboots. Robust form inverts the dependency — have the watchdog read
   the actual address each cycle and rewrite the forward:
   ```powershell
   $ip = (wsl -d Ubuntu -u root -e bash -c "ip -4 -o addr show dev eth0 | awk '{print \$4}' | cut -d/ -f1").Trim()
   netsh interface portproxy set v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$ip
   ```
5. **Minor**: Mermaid flowchart in §4 with no ASCII twin (`SC-DIAGRAM-001` wants both describing the
   same graph); 8 sections against `SC-JOURNAL-v3`'s 13. Softened because the file lives outside the
   UOS repo at `C:\dev\docs\journal`, so those contracts are advisory there — flagged, not asserted.
   `20261105-0615-` prefix is compliant. No private key material exposed (§6.1.4 lists public keys).

**Credit where due**: Root Cause 2 is genuinely good debugging — identifying that `networkingMode=mirrored`
puts WSL2's `ssh.socket` in collision with `iphlpsvc` on `0.0.0.0:2222` while svchost black-holes the
forward is not an obvious failure mode, and it is explained precisely with real `journalctl` evidence.
Root Cause 1 correctly separates the 15-second `wslservice.exe` **distro** idle termination from
`vmIdleTimeout=-1`, which only keeps the utility VM alive. The matrix carries SHA-256 roundtrips and a
negative control (password rejection).

## 6. Correction already delivered to the operator

`.wslconfig` caps WSL2 at **`memory=32GB`**, not the host's 64 GB. That invalidates the
`Qwen3-Coder-Next` (80B-A3B) option ranked fourth in the earlier free-local-model answer — ~45 GB of
experts will not fit a 32 GB allocation and would thrash. The 7B/9B recommendations stand;
`gpuSupport=true` is set, so they can be measured for real over this connection.

## 7. The outstanding deliverable: the Lean module

**Nothing has been written yet.** Request 2 asks to "create or update the lean based code that has
razr15-1 details, ontology and access details".

### What already exists (survey done, 98 files in `formal/lean/`)

| File | Relevance |
|---|---|
| `formal/lean/Razr15_Max_Qwen_Digital_Twin.lean` | **648 lines. The update candidate.** Already carries `Wsl2NodeDescriptor` / `canonicalRazr15Node` (hostname, tailscaleIp `100.114.9.28`, wslInternalIp `172.17.154.247`, sshPort 2222, sshUser `an`, uid/gid 1000, kernel, distro, rootDiskFreeGiB 931) plus `GpuHardwareSpec` (RTX 2070 Max-Q, Turing sm_75, 8192 MiB), MAX 26.8.0 / Mojo 1.3.0 toolchain, the 29-arch registry, GGUF 339-tensor inventory, 24 theorems, and a `lean --run` live probe over SSH `:2222` + HTTP `:8000`. Its focus is MAX/Qwen inference, **not** access control. |
| `formal/lean/Mojo_MAX_Qwen_Full_Ontology_And_Pipeline.lean` | also mentions razr15 |
| `formal/lean/Minimum_Token_Cascade_Theorems.lean` | also mentions razr15 |

Naming convention in `formal/lean/` is CamelCase with **no** timestamp prefix (all 98 files), so the
`YYYYMMDD-HHSS-` mandate applies to the generated *docs*, not to a Lean source file added there.

### Recommended shape (my judgment, not yet agreed with the operator)

A **new** sibling module `formal/lean/Razr15_Remote_Access_Ontology.lean`, namespace
`UOS.Razr15RemoteAccess`, rather than bloating the MAX/Qwen twin — access control and inference
serving are different concerns, and the twin's 24 theorems should not be perturbed. Reuse
`canonicalRazr15Node` by importing it, or restate the node minimally and prove the two agree.

Content to encode:

- **Tailnet node ontology**: nas-1 `100.87.7.78`, vm-1 `100.78.98.18` / `192.168.1.110`,
  nuc-1 `100.96.145.28`, razr15-1 `100.114.9.28`; tailnet `tail55d152.ts.net`.
- **Endpoint algebra**: an inductive over the three published endpoints with
  `(host, port, user, authMethods, transport)` — `razr15-1`/`razr15-wsl`/`wsl` (`100.114.9.28:2222`,
  `an`, pubkey-only, WSL2 sshd), `razr15-wsl-lan` (`192.168.1.177:2222`, `an`), `razr15-win`
  (`100.114.9.28:22`, `abhij`, pubkey+password+kbd-interactive, Windows OpenSSH).
- **Reachability relation** `reachableFrom : Node -> Endpoint -> Bool`, so the §5.1 defect is a
  *theorem*, not prose: `reachableFrom nas1 razr15Win = false`, with the admin-account
  `administrators_authorized_keys` cause as a field. This is the honest encoding — do **not** model
  it as working.
- **Hardening lattice**: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `PubkeyAuthentication yes`, `GatewayPorts no`, `ClientAliveInterval 30`, `ClientAliveCountMax 6`
  per endpoint; then the asymmetry theorem — `hardened wslEndpoint = true ∧ hardened winEndpoint = false`.
- **Identity set**: the 4 distinct authorized identities over 5 key lines (`an@vm-1`,
  `abhij@RAZR15` ×2 = ed25519+rsa, `an@nas-1`, `root@nuc-1`), public-key comments only, no key bytes.
- **Three root causes** as an inductive with their resolutions:
  15s `wslservice.exe` distro idle termination (≠ `vmIdleTimeout`); `mirrored` ↔ `iphlpsvc`
  `0.0.0.0:2222` collision resolved by retaining NAT; password exposure closed on `:2222` only.
- **Component inventory** with a **presence flag per artifact**, since §3 proved two are absent.
  Encode `present : Bool` and prove `∃ a ∈ inventory, a.present = false` — the doc/host divergence
  becomes machine-checked rather than narrative.
- **Liveness-vs-correctness distinction** for the watchdog: a `ProbeKind` inductive
  (`tcpConnect | bannerExchange`) and a theorem that `tcpConnect` does not entail backend liveness
  (finding 3), because `svchost` accepts regardless.
- **12-row verification matrix** with its `:22` coverage hole as a theorem.
- **`lean --run` probe** mirroring the twin's `main` style: anchored keepalive check
  (`ps -eo pid,args | grep -E '^[ ]*[0-9]+ razr15-keepalive'` — never bare `pgrep -af`), `eth0`
  address equality, both `:2222` listeners, sshd effective settings, authorized-key comment set, and
  a **negative control** asserting password auth is refused. Each probe prints observed-vs-expected
  and fails closed.

### Hard constraints on that work

- Zero `sorry`, zero undeclared axioms, zero `Admitted` — the twin's standard. Verify with
  `./tools/lean formal/lean/Razr15_Remote_Access_Ontology.lean` (in-project wrapper,
  `SC-TOOLCHAIN-INPROJECT-001`; Lean 4.33.0 confirmed working this session).
- Encode only facts observed at a named time. The guard unit is **absent** — do not encode it as
  present, and do not encode PID 587 or a 6-line key file.
- No private key material, no token, no `C:\Users\...` secret path contents in the module.
- Helper scripts, if any, must be OCaml or Mojo — never Python (memory `ocaml-or-mojo-helpers-not-python`).
- `formal/lean/` is inside the UOS repo: standalone Jujutsu only, **no native git mutation**.
- A green Lean check is specification evidence at one candidate. It is not runtime admission and not
  two-key verification on its own. EV ceiling stays 93; EV-94..109 remain NOT_ADMITTED; mint no EV number.

## 8. Reproduction recipe for the next session

```bash
# Reach the host (the Windows :22 path will NOT authenticate from nas-1)
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 an@100.114.9.28

# Read the reviewed doc and the Windows-side config from inside WSL2
ssh -p 2222 an@100.114.9.28 'cat /mnt/c/dev/docs/journal/20261105-0615-wsl2-ssh-remote-access-framework.md'
ssh -p 2222 an@100.114.9.28 'cat /mnt/c/Users/abhij/.wslconfig; cat /etc/wsl.conf'

# Clean probe: push a heredoc script over stdin, so no nested-quoting corruption and
# no unanchored pgrep matching the probing shell itself
ssh -p 2222 an@100.114.9.28 'bash -s' < <scratchpad>/probe.sh
```

A working `probe.sh` was used this session; its content is reproduced by the checks in §4 and §7.
It lived in the session scratchpad and is not preserved.

## 9. Carried over, not requested again

- `pi` has never been confirmed to start cleanly after the duplicate-extension removal. Needs the
  operator terminal: `! pi --session 01a19750-3c52-7380-864b-b1893b0c1f91`.
- Measured `nvidia-smi` / tok-per-second benchmarks on razr15-1 could replace the desk-analysis
  local-model table, now that `:2222` works. Offered, never requested.

## 10. Honest state of this handover

Every fact in §4 was observed at `2026-11-05T10:19:44Z`±a few minutes over `ssh -p 2222`. §3 records
a contradiction between an earlier reading in this session and a clean re-probe, and resolves it in
favour of the clean re-probe; the operator has **not** yet been told, so say it plainly next turn.
No file in the repository was created or modified by the review. No Lean code exists for this task.
This document grants no admission and no execution authority; Sa-plan remains the sole execution
authority and no Sa-plan task was claimed for the review.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · EV ceiling 93 · EV-94..109 NOT_ADMITTED · no new EV minted.
