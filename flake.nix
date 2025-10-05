{
  description = "Quicksort WASM experiment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Wasmer's nixpkgs package compiles the full CLI with WASIX support, but as of Oct 2025
        # the x86_64-linux build fails due to linker issues (missing symbols from the WASIX libs).
        # Until that stabilizes we rely on the upstream prebuilt tarball and patch it with
        # autoPatchelf so `wasmer` is always available in the dev shell.
        wasmerBin = pkgs.stdenv.mkDerivation {
          pname = "wasmer-bin";
          version = "5.0.4";
          src = pkgs.fetchzip {
            url = "https://github.com/wasmerio/wasmer/releases/download/v5.0.4/wasmer-linux-amd64.tar.gz";
            sha256 = "sha256-JqCUb6MpCfOyLnUVZXoNpGvRwLI9I9u9jxjfKY+Jx7I=";
            stripRoot = false;
          };
          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.glibc pkgs.zlib pkgs.openssl pkgs.libffi pkgs.libxml2 pkgs.zstd ];
          installPhase = ''
            mkdir -p $out
            cp -R . $out/
          '';
        };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "quicksort-wasm";
          version = "0.1.0";
          src = ./.;
          buildPhase = "true";
          installPhase = ''
            mkdir -p $out
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.wabt
            pkgs.wasmtime.out
            pkgs.wasmedge
            wasmerBin
            pkgs.deno
            pkgs.wazero
            pkgs.hyperfine
            pkgs.wasm-tools
            pkgs.binaryen
            pkgs.jq
            pkgs.python3
          ];
        };
      }
    );
}
