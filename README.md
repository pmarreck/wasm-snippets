# Quicksort WASM

An experiment in hand-authored WebAssembly Text Format (WAT). The core module reads
newline-delimited UTF-8 records from `stdin`, sorts them according to the active
locale (e.g. `LC_ALL=C` or `LC_ALL=en_US.UTF-8`), and writes the sorted list to
`stdout`.

The project intentionally avoids higher-level language toolchains; everything is
built and run directly from `.wat` sources so you can inspect and tweak the
resulting bytecode.

## Repository Layout

- `wat/` – WAT sources (`quicksort.wat` is the main sorter).
- `scripts/wasmbuild` – Compiles `.wat` to `.wasm`, with caching and AOT helpers.
- `scripts/wasmrun` – Executes modules with a chosen runtime (wasmtime, wazero,
  wasmedge, wasmer, deno, plus AOT variants).
- `tests/` – `run.sh` orchestrates all automated checks; `hello_nerds.wat` is the
  fixture module for helper tests.
- `data/` – Sample input (`sample_unsorted.txt`) and benchmark payloads.
- `demos/` – Small explorations of WASI features; `realtime_ns.wat` prints the
  host realtime clock in nanoseconds.
- `bench`, `build_all`, `test` – Top-level convenience wrappers around the
  scripts in `scripts/`.
- `flake.nix` / `.envrc` – Development shell provisioning via Nix and direnv.

## Prerequisites

- Nix 2.18 or newer.
- Optional but recommended: [`direnv`](https://direnv.net/). After cloning,
  run `direnv allow` once so entering the directory loads the dev shell.
- Without direnv, prefix commands with `nix develop -c` (e.g.
  `nix develop -c ./test`).

The dev shell provides all tooling: `wasmtime`, `wasmedge`, `wasmer`, `wazero`,
`deno`, `hyperfine`, `wasm-tools`, `wabt`, `jq`, and `python3` (used for the
benchmark report). The flake pins a prebuilt Wasmer release because the
nixpkgs-provided build currently fails to link on x86_64-linux; see the comment
inside `flake.nix` for details.

## Working With Modules

- Compile manually: `scripts/wasmbuild wat/quicksort.wat`
- Run with default runner (wazero): `scripts/wasmrun wat/quicksort.wat < data/sample_unsorted.txt`
- Choose a runner: `scripts/wasmrun wasmtime wat/quicksort.wat`
- Cache control: set `WASM_BUILD_CACHE=/tmp/wasm-cache` or pass
  `--cache build` / `-o path/to/out.wasm`.
- AOT runners (`wasmer-aot`, `wasmedge-aot`) emit artifacts alongside the `.wasm`
  file (extensions `.wasmer` / `.wasmedge`) and reuse them when timestamps match.

The helpers mimic the “moonrun/moonbuild” workflow: they compare timestamps and
skip rebuilds when the source and cached artifact share the same mtime. If
`wasm-tools` is unavailable they fall back to `wat2wasm`, emitting a warning
because that route requires temporary files.

## Running Tests (TDD)

```
./test
# or
nix develop -c ./test
```

`tests/run.sh` performs two groups of checks:

1. Behavioural parity – For `LC_ALL=C` and `LC_ALL=en_US.UTF-8`, quicksort’s
   output must match the native `sort` command on `data/sample_unsorted.txt`.
2. Helper coverage – Exercises `wasmbuild`/`wasmrun` cache paths, `-o` and
   `--cache` overrides, and the AOT flows for Wasmer and WasmEdge using the
   `tests/hello_nerds.wat` fixture.

## Benchmarking

```
./bench         # defaults to RUNS=20, LC_ALL inherited from your env
RUNS=50 ./bench # override the repetition count
```

The benchmark script:

- Builds `wat/quicksort.wat` once and then runs each runtime via `scripts/wasmrun`.
- Verifies each runner’s output matches native `sort` for the selected locale.
- Feeds the same in-memory dataset (`data/benchmark/strings.txt`) to every
  command, including GNU `sort` as a baseline.
- Invokes `hyperfine` with `-N` semantics using per-runner shim scripts so shell
  startup costs are consistent.
- Stores raw numbers in `build/bench-latest.json` and prints a simple ASCII bar
  chart of mean runtimes (requires `jq`). The summary excludes `sort` when
  ranking the fastest WASM runner.

Tip: adjust `LC_ALL` before running to compare collation behaviours, e.g.
`LC_ALL=en_US.UTF-8 ./bench`.

## Build Everything

```
./build_all            # caches outputs under ./build (or WASM_BUILD_CACHE)
WASM_BUILD_CACHE=out ./build_all
```

This is handy before benchmarking or packaging demos; it ensures cached artifacts
are ready without incurring build work on first run.

## Demos

Each demo is executable thanks to the `wasmrun` shebang:

```
chmod +x demos/realtime_ns.wat    # only needed once if the repo was cloned without exec bits
./demos/realtime_ns.wat
```

`realtime_ns.wat` shows how to call WASI’s `clock_time_get` for nanosecond
resolution. New demo ideas worth exploring:

- Ratatui-based terminal UI compiled to WASI (interactive dashboards in wasm).
- Stopwatch/latency probes comparing realtime vs monotonic clocks.
- Embedding the WasmEdge QuickJS shell for a wasm-hosted JavaScript REPL.

Place future experiments under `demos/` and they’ll automatically benefit from
`./build_all` and `scripts/wasmrun`.

## Troubleshooting

- **Command not found:** Ensure you are inside the Nix dev shell (`direnv allow`
  or `nix develop`).
- **Locales missing:** The tests and benchmarks rely on `LC_ALL=C` and
  `LC_ALL=en_US.UTF-8`. Install the locale data on your host if those names fail.
- **wat2wasm warning:** Install `wasm-tools` to enable streaming compilation and
  avoid temporary files.
- **Benchmark skips a runner:** Check that runtime’s CLI is on `PATH`. AOT modes
  also need `wasmedgec` (for WasmEdge) or the Wasmer CLI to be present.

Happy wasm hacking!
