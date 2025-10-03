{
  description = "Quicksort WASM experiment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ rust-overlay.overlays.default ];
        pkgs = import nixpkgs { inherit system overlays; };
        rust = pkgs.rust-bin.stable."1.78.0".default.override {
          targets = [ "wasm32-wasi" ];
        };
      in {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "quicksort-wasm";
          version = "0.1.0";
          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };
          CARGO_BUILD_TARGET = "wasm32-wasi";
          release = true;
          cargoBuildFlags = [ "--bin" "quicksort-wasm" ];
          installPhase = ''
            mkdir -p $out/bin
            cp target/wasm32-wasi/release/quicksort-wasm.wasm $out/bin/quicksort-wasm.wasm
          '';
          doCheck = false;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            rust
            pkgs.cargo
            pkgs.wasmtime.out
            pkgs.wasmedge
            pkgs.hyperfine
            pkgs.wasm-tools
            pkgs.binaryen
          ];
          shellHook = ''
            export CARGO_TARGET_DIR=$PWD/target
          '';
        };
      }
    );
}
