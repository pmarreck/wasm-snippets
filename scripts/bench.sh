#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

cargo build --release --target wasm32-wasi

module="target/wasm32-wasi/release/quicksort-wasm.wasm"
input_file="data/benchmark/strings.txt"

if [ ! -s "$input_file" ]; then
  echo "Benchmark input $input_file is missing or empty" >&2
  exit 1
fi

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

declare -a runners=("wasmtime" "wasmedge")

for runner in "${runners[@]}"; do
  if ! command -v "$runner" >/dev/null 2>&1; then
    echo "Runner $runner is not available on PATH" >&2
    exit 1
  fi

  bash -lc "$runner $module < $input_file" > "$temp_dir/$runner.txt"
done

for baseline in wasmtime; do
  for runner in "${runners[@]}"; do
    if ! diff -u "$temp_dir/$baseline.txt" "$temp_dir/$runner.txt" >/dev/null; then
      echo "Runner $runner produced output differing from $baseline" >&2
      exit 1
    fi
  done
done

runs="${RUNS:-5}"

echo "Running hyperfine with $runs runs per command..."
hyperfine --warmup 1 --runs "$runs" \
  -n wasmtime "bash -lc 'wasmtime $module < $input_file > /dev/null'" \
  -n wasmedge "bash -lc 'wasmedge $module < $input_file > /dev/null'"
