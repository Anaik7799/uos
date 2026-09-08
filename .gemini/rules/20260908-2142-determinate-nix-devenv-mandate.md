---
trigger: always_on
---

# Determinate Nix & devenv Toolchain Mandate

- **Contract ID**: `SC-NIX-DEVENV-001`
- **Companion Contract**: `SC-TOOLCHAIN-INPROJECT-001`
- **Domain**: Toolchain Provisioning, Reproducibility & BEAM Version Authority
- **Authority**: Operator Directive (2026-09-08) / UOS Canonical Policy
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/files/.gemini/rules/DETERMINATE_NIX_RULE](http://nas-1.tail55d152.ts.net:4100/files/.claude/rules/DETERMINATE_NIX_RULE)
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

3. **OTP 29 ONLY.** `beamMinimal29Packages.erlang` (29.0.5) is the sole admitted
   BEAM. Explicitly barred:
   - the host's **OTP 27** (`/usr/lib/erlang`), and
   - the **OTP-30-era `.beam` artifacts vendored in the zigvm tree**
     (`/home/an/dev/ver/zigvm/src/otp_*.beam`), whose provenance cannot be
     verified with in-project tooling.
   `beamMinimal29` is chosen over the full `erlang` derivation deliberately: the
   latter pulls wxwidgets and webkitgtk (~1.1 GiB closure) that a headless UOS
   node never executes.

4. **In-project surface.** `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, and the
   profile at `toolchains/nix-profile` live in the repository. Toolchain trees
   stay untracked (`.gitignore: toolchains/`) and are pinned by hash in
   `governance/sources/20260908-2103-nix-devenv-toolchain-in-project-installation.json`.
   That manifest SUPERSEDES `20260908-2016-formal-toolchain-in-project-installation.json`,
   whose every path points under the removed `formal/.toolchain/` tree.
   `flake.lock` is mandatory, not optional: without it the FlakeHub wildcard
   `nixpkgs-weekly/*` floats and the flake pins nothing.

5. **Honest boundary — state it, do not hide it.** Nix-provided binaries live in
   `/nix/store` by construction: their RPATHs and ELF interpreter paths are
   absolute store paths, so they CANNOT be relocated under `toolchains/` and
   still execute. The in-project surfaces are the flake, its lock, and the
   profile symlink farm. Any claim that Nix binaries are "physically inside the
   project" is false and must not be written into a journal or ADR.

6. **Materialised exceptions.** Three toolchains are materialised in-project as
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

7. **No PATH races.** `tools/lib/uos-toolchain.sh` (`uos_env`) and the devenv
   `enterShell` PREPEND in-project paths so a stray `/usr/bin/erl` cannot win.
   `uos_have` reports absence honestly; callers fail closed and never silently
   substitute a host binary.

---

## 3. Machine Enforcement

1. `bash -c 'source tools/lib/uos-toolchain.sh; uos_toolchain_report'` — every
   entrypoint must resolve under `$UOS_ROOT`.
2. `devenv test` — `enterTest` fails closed unless `otp_release == "29"`.
3. Toolchain hashes are pinned in the governance installation manifest.
4. `nix flake lock 'path:$UOS_ROOT'` — the explicit `path:` URL is REQUIRED.
   A bare `nix flake` command fails with libgit2 error 6 because an empty
   stray `.git` directory in the repository root makes Nix classify the tree
   as a Git flake. It holds no Git repository and no native Git mutation has
   occurred, so canonical policy section 4 is intact; the workaround stands
   until the directory is removed.
5. `tools/quint` (Quint 0.32.0) replaces `tools/quint-eval`, whose backend —
   the standalone Rust evaluator 0.6.0 — is no longer installed. A wrapper
   fronting an absent binary is barred: fail closed, do not fabricate.