{
  # =============================================================================
  # UOS in-project toolchain flake (SC-TOOLCHAIN-INPROJECT-001)
  # -----------------------------------------------------------------------------
  # Operator mandates (2026-09-08):
  #   1. "all tool chain must be in uos project, mandatory requirement"
  #   2. "use only otp 29 in uos" -- the host's OTP 27 and the zigvm tree's
  #      vendored OTP-30 .beam artifacts are BOTH barred.
  #   3. "get it from determinate nixos or devenv if possible" -- prefer
  #      substituted binaries from the cache over building from source.
  #
  # This flake is the reproducible PIN. `nix develop` yields a shell in which
  # every pinned toolchain resolves ahead of any host binary, so a stray
  # /usr/bin/erl (OTP 27) cannot win a PATH race.
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
      ];
    in {
      packages.${system} = {
        inherit otp29;
        default = pkgs.buildEnv {
          name = "uos-toolchain";
          paths = toolchain;
        };
      };

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
          echo "UOS toolchain: OTP $(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().') (OTP 29 only), zig $(zig version), z3 $(z3 --version | cut -d" " -f3)"
        '';
      };
    };
}
