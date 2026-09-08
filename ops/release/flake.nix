{
  description = "Pinned UOS release-checker build dependencies; no Python or application deployment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c25784012c9982bca5b3e0de87e90bbdac8927d3";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system}.default = pkgs.buildEnv {
        name = "uos-release-checker-dependencies";
        paths = [ pkgs.stdenv.cc pkgs.curl (pkgs.lib.getLib pkgs.curl) pkgs.curl.dev pkgs.pkg-config pkgs.zlib pkgs.zlib.dev ];
        pathsToLink = [ "/bin" "/lib" "/include" ];
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.stdenv.cc pkgs.curl pkgs.pkg-config ];
        buildInputs = [ pkgs.curl pkgs.zlib ];
      };
    };
}
