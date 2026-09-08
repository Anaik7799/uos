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
{
  name = "uos";

  packages = [
    pkgs.beamMinimal29Packages.erlang   # 29.0.5 -- the sole admitted BEAM
    pkgs.beam29Packages.rebar3          # built against OTP 29, not 27
    pkgs.zig                            # 0.16.0 -- engines/zigvm README pin
    pkgs.z3                             # 4.16.0 -- bounded solver workers only
    pkgs.quint                          # 0.32.0 -- .qnt front-end compiler
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

  # Fail closed: a shell that silently came up on the host's OTP 27 is worse
  # than no shell, because every build artefact it produces is mislabelled.
  enterTest = ''
    otp=$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')
    if [ "$otp" != "29" ]; then
      echo "SC-NIX-DEVENV-001 violation: OTP $otp active, UOS admits OTP 29 only" >&2
      exit 1
    fi
    echo "OTP $otp OK"
  '';
}
