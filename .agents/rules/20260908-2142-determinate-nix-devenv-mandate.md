---
trigger: always_on
---

# Determinate Nix & devenv Toolchain Mandate

- **Contract ID**: `SC-NIX-DEVENV-001`
- **Companion Contract**: `SC-TOOLCHAIN-INPROJECT-001`
- **Domain**: Toolchain Provisioning, Reproducibility & BEAM Version Authority
- **Authority**: Operator Directive (2026-09-08) / UOS Canonical Policy
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/files/.agents/rules/DETERMINATE_NIX_RULE](http://nas-1.tail55d152.ts.net:4100/files/.claude/rules/DETERMINATE_NIX_RULE)
- **Status**: ACTIVE & ENFORCED

#fractal-l0 #fractal-l4 #fractal-l7 #zero-muda #km-triad #stamp-stpa #toolchain

---

## 1. Operator Directives

> **"all tool chain must be in uos project, mandatory requirement"**
> **"do not use zig vrsion of otp, use only otp 29 in uos"**
> **"get it from determinate nixos or devenv if possible. do not build it"**
> **"add mandatory rule to use determinate nix and devenv. mandatory"**

---

## 2. Invariants

1. **Determinate Nix is the provisioning authority.** New toolchains are obtained
   through Determinate Nix (`nix profile add --profile toolchains/nix-profile`)
   or devenv. Ad-hoc host package installs, `$HOME` toolchains, and toolchains
   consumed from external evidence trees (`/home/an/dev/ver/*`) are barred:
   canonical policy section 3 designates those trees read-only evidence, which
   makes them illegitimate runtime dependencies.

2. **Substitute, do not build.** Prefer a cached binary substitution over a
   source build. A source build is permitted only when no substituter provides
   the artifact, and it must be recorded in the governance manifest with the
   reason.

3. **Guards compare DERIVATIONS, not release numbers.** `erlang:system_info(otp_release)`
   answers `"29"` for 29.0.5 and for 29.0.6 alike, so a release-number assertion is
   structurally incapable of separating the pinned BEAM from an unpinned one. This is
   not hypothetical: `/nix/store/qq9f90d5…-erlang-29.0.6` sat hardcoded in
   `tools/release_process.ml` while every release-number check in the tree stayed
   green. Every guard MUST compare `readlink -f "$(command -v erl)"` against the
   store path the lock resolves.

4. **OTP 29 ONLY.** `beamMinimal29Packages.erlang` (29.0.5) is the sole admitted
   BEAM. Explicitly barred:
   - the host's **OTP 27** (`/usr/lib/erlang`), and
   - the **OTP-30-era `.beam` artifacts vendored in the zigvm tree**
     (`/home/an/dev/ver/zigvm/src/otp_*.beam`), whose provenance cannot be
     verified with in-project tooling.
   `beamMinimal29` is chosen over the full `erlang` derivation deliberately: the
   latter pulls wxwidgets and webkitgtk (~1.1 GiB closure) that a headless UOS
   node never executes.

5. **In-project surface.** `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, and the
   profile at `toolchains/nix-profile` live in the repository. Toolchain trees
   stay untracked (`.gitignore: toolchains/`) and are pinned by hash in
   `governance/sources/20260908-2103-nix-devenv-toolchain-in-project-installation.json`.
   That manifest SUPERSEDES `20260908-2016-formal-toolchain-in-project-installation.json`,
   whose every path points under the removed `formal/.toolchain/` tree.
   `flake.lock` is mandatory, not optional: without it the FlakeHub wildcard
   `nixpkgs-weekly/*` floats and the flake pins nothing.

6. **Honest boundary — state it, do not hide it.** Nix-provided binaries live in
   `/nix/store` by construction: their RPATHs and ELF interpreter paths are
   absolute store paths, so they CANNOT be relocated under `toolchains/` and
   still execute. The in-project surfaces are the flake, its lock, and the
   profile symlink farm. Any claim that Nix binaries are "physically inside the
   project" is false and must not be written into a journal or ADR.

7. **Materialised exceptions.** Three toolchains are materialised in-project as
   real directories rather than taken from Nix, each for a stated reason:
   - **Gleam 1.16.0** — the project pin; nixpkgs currently offers 1.18.1 and the
     bump is unverified against `apps/*`.
   - **opam switch (OCaml 5.5.0 + dune 3.23.1)** — Hermes needs the full package
     set (cryptokit, gospel, z3, sqlite3, domainslib); nixpkgs `ocaml` alone
     does not supply it. Verified: `dune build` of `engines/hermes` passes.
   - **Lean 4.33.0** — `formal/lean/*.lean` are verified to check at 4.33.0;
     nixpkgs currently offers 4.30.0.
   Each exception is a version-pin decision, not a licence to drift; revisit when
   the pinned version is verified.

13. **Jujutsu is a pinned toolchain.** Canonical policy section 4 makes standalone JJ
   the sole VCS, so the binary that reads and could write `.jj/` is pinned from the
   Nix profile, never taken from `~/.cargo/bin`. The locked nixpkgs supplies the same
   version already managing the repository, so the swap carries no repo-format risk —
   verify that BEFORE swapping, never after.

10. **Tracked and verifiably useable.** All tooling MUST be tracked in Jujutsu and
   MUST be proven to run. `test -x` is not evidence of use, and neither is exit
   status alone: a zero-byte file with the execute bit set is a valid empty shell
   script that exits 0 and prints nothing. Preflight probes therefore EXECUTE each
   entrypoint, require non-empty output unless the tool is legitimately silent,
   and prefer making the tool do its job (compile, run, solve, typecheck) over
   printing a version. Tracking is asked of the VCS, never inferred from the
   filesystem.

11. **No tool bypasses the resolver.** A hardcoded absolute toolchain path is a
   violation even when it happens to work, because it is invisible to
   `uos_toolchain_report`: that report can read 19/19 PRESENT while the file under
   review uses none of those 19. Anything that resolves a toolchain goes through
   `tools/lib/uos-toolchain.sh` or a table proven equal to it. Host OS utilities
   (`cp`, `curl`, `printf`) are not toolchains and stay on host paths, but must be
   named as such rather than left incidental.

12. **No PATH races.** `tools/lib/uos-toolchain.sh` (`uos_env`) and the devenv
   `enterShell` PREPEND in-project paths so a stray `/usr/bin/erl` cannot win.
   `uos_have` reports absence honestly; callers fail closed and never silently
   substitute a host binary.

---

## 3. Machine Enforcement

1. `bash -c 'source tools/lib/uos-toolchain.sh; uos_toolchain_report'` — every
   entrypoint must resolve under `$UOS_ROOT`.
2. `devenv test` — `enterTest` fails closed unless `otp_release == "29"`.
3. Toolchain hashes are pinned in the governance installation manifest.
4. `nix flake check 'path:$UOS_ROOT'` — `checks.toolchain-pin` fails the FLAKE,
   not merely a shell, unless the pinned erl exists, reports OTP 29 and has not
   escaped the store into `/usr` or `/home`.
5. `bash -c 'source tools/lib/uos-toolchain.sh; uos_toolchain_verify'` — the
   LOCALITY gate: no entrypoint may resolve under `$HOME`, `/usr`, `/opt` or
   `/home/an/dev/ver/*`. It deliberately does not hardcode a store path;
   identity is the flake's authority, locality is the shell's, and a third
   source of truth would drift silently.
6. `ocaml tools/release_process.ml toolchain` — proves the OCaml table is equal
   to the shell table arm for arm, and that erl resolves to a store path outside
   every barred tree. Runs as a preflight before EVERY command of that tool.
7. Any `nix flake` command MUST use the explicit `path:$UOS_ROOT` URL. This is
   permanent, not a workaround: Nix ascends looking for a git root and finds
   empty `.git` marker directories both in the repository and in its parent,
   neither of which git itself recognises as a repository. Removing one only
   makes Nix climb to the next. No native Git mutation has occurred and
   canonical policy section 4 is intact.
8. `bash tools/preflight` — the single gate to run before work. Six arms:
   resolver, useable (executes all 20 entrypoints), wrapper, tracked (asks
   Jujutsu), parity, and — with `--full` — identity via `nix flake check` and
   `devenv test`. Exit 0 only if every arm passes; JSON on stdout, table on
   stderr. Observed 31/31 PASS with `--full`.
9. `tools/quint` (Quint 0.32.0) replaces `tools/quint-eval`, whose backend —
   the standalone Rust evaluator 0.6.0 — is no longer installed. A wrapper
   fronting an absent binary is barred: fail closed, do not fabricate.