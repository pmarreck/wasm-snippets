#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

wasmbuild="$project_root/scripts/wasmbuild"
wasmrun="$project_root/scripts/wasmrun"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

hello_wat="tests/hello_nerds.wat"
expected_output="hello, nerds!"

quicksort_module="$project_root/scripts/quicksort"
ns_demo="$project_root/demos/ns"
input_file="data/sample_unsorted.txt"

require_helpers() {
	if [ ! -x "$wasmbuild" ] || [ ! -x "$wasmrun" ]; then
		echo "test harness requires scripts/wasmbuild and scripts/wasmrun" >&2
		exit 1
	fi
}

check_inputs() {
	if [ ! -s "$input_file" ]; then
		echo "Input fixture $input_file is missing or empty" >&2
		exit 1
	fi
}

run_quicksort_locale() {
	local locale="$1"
	local locale_dir="$tmpdir/locale-$locale"
	mkdir -p "$locale_dir"
	local expected="$locale_dir/expected.txt"
	local actual="$locale_dir/actual.txt"

	if ! LC_ALL="$locale" sort "$input_file" > "$expected"; then
		echo "sort failed under LC_ALL=$locale; ensure the locale is installed" >&2
		exit 1
	fi

	if ! LC_ALL="$locale" "$wasmrun" --cache build wasmtime "$quicksort_module" < "$input_file" > "$actual"; then
		echo "wasm run failed for LC_ALL=$locale" >&2
		exit 1
	fi

	diff -u "$expected" "$actual"
	printf 'quicksort matches sort for LC_ALL=%s\n' "$locale"
}

run_ns_override() {
	local expected="1700000000.123456789"
	local output
	output=$(printf '\x15\xcd\x85\x3d\xfe\x9c\x97\x17' | "$ns_demo")
	output=${output%$'\n'}
	if [ "$output" != "$expected" ]; then
		echo "ns stdin override mismatch: $output" >&2
		exit 1
	fi
	printf 'ns stdin override via pipe ok\n'
}

run_helper_tests() {
	# 1. Default build path.
	local default_path
	default_path=$($wasmbuild "$hello_wat")
	if [ ! -f "$default_path" ]; then
		echo "wasmbuild default path missing" >&2
		exit 1
	fi

	# 2. Respect WASM_BUILD_CACHE.
	export WASM_BUILD_CACHE="$tmpdir/cache-env"
	local cache_env_path
	cache_env_path=$($wasmbuild "$hello_wat")
	if [ "$cache_env_path" != "$tmpdir/cache-env/hello_nerds.wasm" ]; then
		echo "WASM_BUILD_CACHE not honored" >&2
		exit 1
	fi
	if [ ! -f "$cache_env_path" ]; then
		echo "wasmbuild cache output missing" >&2
		exit 1
	fi
	unset WASM_BUILD_CACHE

	# 3. --cache flag overrides env/default.
	local cache_flag_path
	cache_flag_path=$($wasmbuild --cache "$tmpdir/cache-flag" "$hello_wat")
	if [ "$cache_flag_path" != "$tmpdir/cache-flag/hello_nerds.wasm" ]; then
		echo "--cache flag not honored" >&2
		exit 1
	fi

	# 4. -o option overrides cache.
	local custom_path="$tmpdir/custom/output.wasm"
	$wasmbuild --cache "$tmpdir/cache-ignored" -o "$custom_path" "$hello_wat" >/dev/null
	if [ ! -f "$custom_path" ]; then
		echo "wasmbuild -o output missing" >&2
		exit 1
	fi

	# 5. wasmrun executes and caches using wazero.
	local run_output
	run_output=$($wasmrun --cache "$tmpdir/run-cache" wazero "$hello_wat")
	run_output=${run_output%$'\n'}
	if [ "$run_output" != "$expected_output" ]; then
		echo "wasmrun output mismatch: $run_output" >&2
		exit 1
	fi

	# 6. wasmrun with -o writes specified artifact.
	local run_custom="$tmpdir/run-custom/out.wasm"
	$wasmrun -o "$run_custom" wasmtime "$hello_wat" >/dev/null
	if [ ! -f "$run_custom" ]; then
		echo "wasmrun -o did not produce artifact" >&2
		exit 1
	fi

	# 7. wasmrun produces Wasmer AOT artefact and executes it.
	local wasmer_cache="$tmpdir/wasmer-cache"
	run_output=$($wasmrun --cache "$wasmer_cache" wasmer-aot "$hello_wat")
	run_output=${run_output%$'\n'}
	if [ "$run_output" != "$expected_output" ]; then
		echo "wasmrun wasmer-aot output mismatch: $run_output" >&2
		exit 1
	fi
	if [ ! -f "$wasmer_cache/hello_nerds.wasmer" ]; then
		echo "wasmer-aot cache artefact missing" >&2
		exit 1
	fi

	# 8. wasmrun produces Wasmedge AOT artefact and executes it.
	local wasmedge_cache="$tmpdir/wasmedge-cache"
	run_output=$($wasmrun --cache "$wasmedge_cache" wasmedge-aot "$hello_wat")
	run_output=${run_output%$'\n'}
	if [ "$run_output" != "$expected_output" ]; then
		echo "wasmrun wasmedge-aot output mismatch: $run_output" >&2
		exit 1
	fi
	if [ ! -f "$wasmedge_cache/hello_nerds.wasmedge" ]; then
		echo "wasmedge-aot cache artefact missing" >&2
		exit 1
	fi

	printf 'wasm helper tests passed\n'
}

require_helpers
check_inputs

# Ensure quicksort artefact exists at least once before running comparisons.
"$wasmbuild" --cache build "$quicksort_module" >/dev/null

run_quicksort_locale C
run_quicksort_locale en_US.UTF-8

run_ns_override
run_helper_tests
