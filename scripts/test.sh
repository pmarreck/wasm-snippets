#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

cargo build --release --target wasm32-wasi

wasmtime target/wasm32-wasi/release/quicksort-wasm.wasm \
  < data/sample_unsorted.txt \
  | diff -u data/sample_sorted.txt -
