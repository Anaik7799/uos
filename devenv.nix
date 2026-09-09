{ pkgs, ... }:
# =============================================================================
# UOS developer environment (SC-NIX-DEVENV-001, SC-TOOLCHAIN-INPROJECT-001)
# -----------------------------------------------------------------------------
# Operator mandate (2026-09-08): Determinate Nix and devenv are MANDATORY for
# toolchain provisioning. Ad-hoc host installs, $HOME toolchains, and toolchains
# consumed from external evidence trees (/home/an/dev/ver/*) are barred.
#
# BEAM policy: OTP 29 ONLY. beamMinimal29 is used deliberately -- the full
# erlang derivation pulls wxwidgets + webkitgtk (~1.1 GiB closure) that a
# headless UOS node never executes.
# =============================================================================
let
  otp29 = pkgs.beamMinimal29Packages.erlang;
  # The exact erl this environment admits. Guards compare against this PATH, not
  # against the OTP release number: 29.0.5 and 29.0.6 both report otp_release
  # "29", so a release-number assertion cannot tell the pinned BEAM from an
  # unpinned one. That precise gap let /nix/store/...-erlang-29.0.6 into
  # tools/release_process.ml while every release-number check stayed green.
  pinnedErl = "${otp29}/lib/erlang/bin/erl";
in
{
  name = "uos";

  packages = [
    otp29                               # 29.0.5 -- the sole admitted BEAM
    pkgs.beam29Packages.rebar3          # built against OTP 29, not 27
    pkgs.zig                            # 0.16.0 -- engines/zigvm README pin
    pkgs.z3                             # 4.16.0 -- bounded solver workers only
    pkgs.quint                          # 0.32.0 -- .qnt front-end compiler
    pkgs.jujutsu                        # 0.44.0 -- the sole VCS (policy 4)
  ];

  enterShell = ''
    export UOS_ROOT="$DEVENV_ROOT"
    # Toolchains materialised in-project (Gleam 1.16.0 pinned by the project,
    # the opam switch with its cryptokit/gospel/z3 package set, and Lean 4.33.0
    # against which formal/lean/*.lean actually check) take priority over any
    # Nix or host equivalent.
    export PATH="$UOS_ROOT/toolchains/gleam-1.16.0/bin:$UOS_ROOT/toolchains/opam-ocaml/bin:$UOS_ROOT/toolchains/lean-4.33.0/bin:$PATH"
    export OPAM_SWITCH_PREFIX="$UOS_ROOT/toolchains/opam-ocaml"
    export CARGO_HOME="$UOS_ROOT/toolchains/cargo"
    export RUSTUP_HOME="$UOS_ROOT/toolchains/rustup"
    export ZIG_GLOBAL_CACHE_DIR="$UOS_ROOT/toolchains/.cache/zig"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
  '';

  # Fail closed: a shell that silently came up on the host's OTP 27 -- or on an
  # unpinned OTP 29 -- is worse than no shell, because every artefact it produces
  # is mislabelled. Three arms, each catching a failure the others cannot:
  #
  #   1. RELEASE   -- catches OTP 27 and any non-29 BEAM.
  #   2. DERIVATION -- catches an OTP 29 that is not THIS OTP 29 (the 29.0.6 case).
  #   3. PROFILE PARITY -- catches devenv and flake.nix drifting apart, i.e. the
  #      devenv nixpkgs resolving a different erlang than the one installed into
  #      toolchains/nix-profile from flake.nix. Skipped, loudly, when the profile
  #      is absent rather than silently passing.
  enterTest = ''
    set -eu

    otp=$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')
    if [ "$otp" != "29" ]; then
      echo "SC-NIX-DEVENV-001 violation [release]: OTP $otp active, UOS admits OTP 29 only" >&2
      exit 1
    fi

    actual_erl="$(readlink -f "$(command -v erl)")"
    if [ "$actual_erl" != "${pinnedErl}" ]; then
      echo "SC-NIX-DEVENV-001 violation [derivation]: erl resolves to $actual_erl; pin admits ${pinnedErl}" >&2
      echo "  Both may report OTP 29. Only the pinned derivation is admitted." >&2
      exit 1
    fi

    profile_erl="$UOS_ROOT/toolchains/nix-profile/bin/erl"
    if [ -x "$profile_erl" ]; then
      resolved_profile_erl="$(readlink -f "$profile_erl")"
      if [ "$resolved_profile_erl" != "${pinnedErl}" ]; then
        echo "SC-NIX-DEVENV-001 violation [profile parity]: toolchains/nix-profile erl is" >&2
        echo "  $resolved_profile_erl but devenv pins ${pinnedErl}." >&2
        echo "  devenv.lock and flake.lock have drifted; reinstall the profile from flake.nix." >&2
        exit 1
      fi
      echo "profile parity OK: $resolved_profile_erl"
    else
      echo "WARNING: toolchains/nix-profile/bin/erl absent; profile parity NOT checked" >&2
    fi

    echo "OTP $otp OK at ${pinnedErl}"
  '';
}
