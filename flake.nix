{
  # =============================================================================
  # UOS in-project toolchain flake (SC-TOOLCHAIN-INPROJECT-001, SC-NIX-DEVENV-001)
  # -----------------------------------------------------------------------------
  # Operator mandates (2026-09-08):
  #   1. "all tool chain must be in uos project, mandatory requirement"
  #   2. "use only otp 29 in uos" -- the host's OTP 27 and the zigvm tree's
  #      vendored OTP-30 .beam artifacts are BOTH barred.
  #   3. "get it from determinate nixos or devenv if possible" -- prefer
  #      substituted binaries from the cache over building from source.
  #
  # This flake is the reproducible PIN, and flake.lock is what makes that sentence
  # true. Without the lock the FlakeHub `nixpkgs-weekly/*` wildcard floats and this
  # file pins nothing.
  #
  # HONEST BOUNDARY: Nix-provided binaries live in /nix/store by construction --
  # their RPATHs and interpreter paths are absolute store paths, so they cannot
  # be relocated under toolchains/ and still run. The in-project surfaces are
  # this flake, its lock, and the profile symlink farm at toolchains/nix-profile.
  # Toolchains that Nix does NOT provide adequately are materialised in-project
  # as real directories under toolchains/ (see below).
  # =============================================================================
  description = "UOS pinned toolchain (OTP 29 only)";

  inputs.nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*.tar.gz";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # OTP 29 ONLY. beamMinimal29 avoids the wx/webkitgtk closure (~1.1 GiB)
      # that the full erlang derivation drags in; UOS runs headless.
      otp29 = pkgs.beamMinimal29Packages.erlang;

      toolchain = [
        otp29                          # 29.0.5 -- the sole admitted BEAM
        pkgs.beam29Packages.rebar3     # built against OTP 29
        pkgs.zig                       # 0.16.0 -- engines/zigvm README pin
        pkgs.z3                        # 4.16.0
        pkgs.quint                     # 0.32.0 -- .qnt front-end compiler
        pkgs.jujutsu                   # 0.44.0 -- the sole VCS; see note below
        pkgs.nodejs_22                 # 22.23.2 -- complete npm (see note)
        pkgs.coreutils                 # 9.x -- cp/printf/sleep/false, see note below
      ];

      # The exact erl this pin admits. Every guard compares against THIS path and
      # never against the OTP release number alone: 29.0.5 and 29.0.6 both report
      # otp_release "29", so a release-number check cannot distinguish the pinned
      # BEAM from an unpinned one that merely happens to also be OTP 29. That gap
      # is exactly how /nix/store/...-erlang-29.0.6 reached tools/release_process.ml
      # while every release-number assertion in the tree stayed green.
      pinnedErl = "${otp29}/lib/erlang/bin/erl";

      # coreutils is pinned because tools/release_process.ml shells out to cp,
      # printf, sleep and false on absolute /usr/bin paths. Those are OS utilities
      # rather than language toolchains, so the mandate did not bar them -- but on
      # THIS host /usr/bin/timeout is a symlink into a uutils (Rust) coreutils
      # install, so "the host coreutils" are not the GNU ones and their behaviour
      # is not the behaviour anyone assumed. Pinning removes the assumption.
      #
      # nodejs_22 replaces a hand-materialised toolchains/node-22 tree whose npm
      # was INCOMPLETE: its bundled node_modules was missing semver, so npm died
      # with "Cannot find module 'semver/functions/satisfies'" the moment it took
      # any path that loads config. `npm --version` still answered 9.2.0, which is
      # why it looked healthy -- a present, self-identifying, non-working tool.
      #
      # jujutsu is provisioned here rather than consumed from ~/.cargo/bin because
      # canonical policy section 4 makes JJ the sole VCS: a tool that reads and
      # could write .jj/ must be pinned, not whatever the host happens to have.
      # The locked nixpkgs supplies 0.44.0 -- the same version already managing
      # this repository -- so the swap carries no repo-format risk.
    in {
      packages.${system} = {
        inherit otp29;
        default = pkgs.buildEnv {
          name = "uos-toolchain";
          paths = toolchain;
        };
      };

      # `nix flake check` enforces the pin without entering a shell. This is the
      # machine gate: it fails the flake itself, not merely an interactive session.
      checks.${system}.toolchain-pin = pkgs.runCommand "uos-toolchain-pin-check" { } ''
        set -eu
        erl_bin="${pinnedErl}"
        test -x "$erl_bin" || { echo "pinned erl missing: $erl_bin" >&2; exit 1; }
        release=$("$erl_bin" -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')
        test "$release" = "29" || { echo "pinned erl reports OTP $release, expected 29" >&2; exit 1; }
        # Negative arm: the check must not be satisfiable by the host BEAM.
        case "$erl_bin" in
          /usr/*|/home/*) echo "pin escaped the store: $erl_bin" >&2; exit 1 ;;
        esac
        echo "pinned erl $erl_bin reports OTP $release" > $out
      '';

      devShells.${system}.default = pkgs.mkShell {
        packages = toolchain;
        shellHook = ''
          export UOS_ROOT="$PWD"
          # Toolchains materialised in-project (not from Nix) still take priority.
          export PATH="$UOS_ROOT/toolchains/gleam-1.16.0/bin:$UOS_ROOT/toolchains/opam-ocaml/bin:$UOS_ROOT/toolchains/lean-4.33.0/bin:$PATH"
          export OPAM_SWITCH_PREFIX="$UOS_ROOT/toolchains/opam-ocaml"
          export CARGO_HOME="$UOS_ROOT/toolchains/cargo"
          export RUSTUP_HOME="$UOS_ROOT/toolchains/rustup"
          export ZIG_GLOBAL_CACHE_DIR="$UOS_ROOT/toolchains/.cache/zig"
          # Fail closed on the DERIVATION, not the release number.
          actual_erl="$(readlink -f "$(command -v erl)")"
          if [ "$actual_erl" != "${pinnedErl}" ]; then
            echo "SC-NIX-DEVENV-001 violation: erl resolves to $actual_erl; pin admits ${pinnedErl}" >&2
            exit 1
          fi
          echo "UOS toolchain: OTP $(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().') pinned at ${pinnedErl}; zig $(zig version); z3 $(z3 --version | cut -d' ' -f3); $(jj --version)"
        '';
      };
    };
}
