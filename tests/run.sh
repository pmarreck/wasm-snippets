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

run_factor_tests() {
	local expected stdout_file stderr_file

	expected="$tmpdir/factor-expected.txt"
	stdout_file="$tmpdir/factor-stdout.txt"
	stderr_file="$tmpdir/factor-stderr.txt"

	printf '4294967295: 3 5 17 257 65537\n' >"$expected"
	if ! diff -u "$expected" <(printf '4294967295\n' | PATH="$project_root/scripts:$PATH" timeout 5s "$project_root/demos/factor"); then
		echo "factor happy-path mismatch" >&2
		exit 1
	fi

	if ! printf 'wat\n12\n' | PATH="$project_root/scripts:$PATH" timeout 5s "$project_root/demos/factor" >"$stdout_file" 2>"$stderr_file"; then
		echo "factor demo failed on mixed input" >&2
		exit 1
	fi

	printf '12: 2 2 3\n' >"$expected"
	if ! diff -u "$expected" "$stdout_file"; then
		echo "factor stdout mismatch for mixed input" >&2
		exit 1
	fi

	printf 'factor: invalid input: wat\n' >"$expected"
	if ! diff -u "$expected" "$stderr_file"; then
		echo "factor stderr mismatch for mixed input" >&2
		exit 1
	fi

	printf 'factor demo checks ok\n'
}

run_progressbar_tests() {
	local output progressbar_last_newline

	progressbar_env_assignments() {
		local mode="$1"
		local columns="$2"
	case "$mode" in
	override)
		printf 'COLUMNS_OVERRIDE=%s\n' "$columns"
		;;
	native)
		printf 'COLUMNS=%s\n' "$columns"
		;;
	both)
		local override_value native_value
		override_value=${columns%%:*}
		if [ "$override_value" = "$columns" ]; then
			native_value=$override_value
		else
			native_value=${columns#*:}
		fi
		printf 'COLUMNS_OVERRIDE=%s\nCOLUMNS=%s\n' "$override_value" "$native_value"
		;;
	none | *)
		;;
	esac
}

	run_progressbar_capture() {
		local _var="$1"
		local mode="$2"
		local columns="$3"
		local input="$4"
		shift 4
		local args=("$@")
		local marker="__PB_STATUS__"
		local combined output_text status has_newline=0
		local env_args=()
		local assignment

		while IFS= read -r assignment; do
			env_args+=("$assignment")
		done < <(progressbar_env_assignments "$mode" "$columns")

		combined=$(
			{
				printf '%s' "$input" |
					env -i PATH="$project_root/scripts:$PATH" \
						LC_ALL="${LC_ALL:-C}" \
						"${env_args[@]}" \
						timeout 5s "$project_root/demos/progressbar" "${args[@]}" 2>&1
				status=${PIPESTATUS[1]}
				printf '%s%d' "$marker" "$status"
			}
		)
		if [ "$combined" = "${combined%$marker*}" ]; then
			echo "progressbar capture missing status marker" >&2
			exit 1
		fi
		status=${combined##*$marker}
		output_text=${combined%$marker*}
		if [[ $output_text == *$'\n' ]]; then
			has_newline=1
			output_text=${output_text%$'\n'}
		fi

		if [ "$status" -eq 124 ]; then
			pkill -f "$project_root/demos/progressbar" 2>/dev/null || true
			echo "progressbar command timed out" >&2
			exit 1
		elif [ "$status" -ne 0 ]; then
			pkill -f "$project_root/demos/progressbar" 2>/dev/null || true
			echo "progressbar command failed with status $status" >&2
			exit 1
		fi
		if pgrep -f "$project_root/demos/progressbar" >/dev/null 2>&1; then
			pkill -f "$project_root/demos/progressbar" 2>/dev/null || true
			echo "progressbar process leaked after completion" >&2
			exit 1
		fi

		progressbar_last_newline=$has_newline
		printf -v "$_var" '%s' "$output_text"
	}

	run_progressbar_expect_error() {
		local mode="$1"
		local columns="$2"
		local input="$3"
		local expected_message="$4"
		shift 4
		local args=("$@")
		local marker="__PB_STATUS__"
		local combined output_text status
		local env_args=()
		local assignment

		while IFS= read -r assignment; do
			env_args+=("$assignment")
		done < <(progressbar_env_assignments "$mode" "$columns")

		combined=$(
			{
				printf '%s' "$input" |
					env -i PATH="$project_root/scripts:$PATH" \
						LC_ALL="${LC_ALL:-C}" \
						"${env_args[@]}" \
						timeout 5s "$project_root/demos/progressbar" "${args[@]}" 2>&1
				status=${PIPESTATUS[1]}
				printf '%s%d' "$marker" "$status"
			}
		)
		if [ "$combined" = "${combined%$marker*}" ]; then
			echo "progressbar error capture missing status marker" >&2
			exit 1
		fi
		status=${combined##*$marker}
		output_text=${combined%$marker*}
		output_text=${output_text%$'\n'}

		if [ "$status" -eq 124 ]; then
			pkill -f "$project_root/demos/progressbar" 2>/dev/null || true
			echo "progressbar command timed out during error check" >&2
			exit 1
		elif [ "$status" -ne 1 ]; then
			pkill -f "$project_root/demos/progressbar" 2>/dev/null || true
			echo "progressbar expected exit 1, got $status" >&2
			exit 1
		fi
		if pgrep -f "$project_root/demos/progressbar" >/dev/null 2>&1; then
			pkill -f "$project_root/demos/progressbar" 2>/dev/null || true
			echo "progressbar process leaked after error" >&2
			exit 1
		fi
		if [ "$output_text" != "$expected_message" ]; then
			printf 'progressbar error message mismatch: %q\n' "$output_text" >&2
			exit 1
		fi
	}

	run_progressbar_capture output override 10 $'50\n'
	if [ "${progressbar_last_newline:-0}" -ne 1 ]; then
		echo "progressbar 50% missing newline" >&2
		exit 1
	fi
	if [ "$output" != $'█████' ]; then
		echo "progressbar 50% mismatch" >&2
		printf 'got: %q\n' "$output" >&2
		exit 1
	fi

	run_progressbar_capture output override 8 $'75\n' -c
	if [ "${progressbar_last_newline:-0}" -ne 0 ]; then
		echo "progressbar -c emitted newline" >&2
		exit 1
	fi
	if [ "$output" != $'██████  ' ]; then
		echo "progressbar -c mismatch" >&2
		printf 'got: %q\n' "$output" >&2
		exit 1
	fi

	run_progressbar_capture output native 12 $'25\n'
	if [ "${progressbar_last_newline:-0}" -ne 1 ]; then
		echo "progressbar native columns missing newline" >&2
		exit 1
	fi
	if [ "$output" != $'███' ]; then
		echo "progressbar native columns mismatch" >&2
		printf 'got: %q\n' "$output" >&2
		exit 1
	fi

	run_progressbar_capture output both '6:20' $'50\n'
	if [ "${progressbar_last_newline:-0}" -ne 1 ]; then
		echo "progressbar override precedence missing newline" >&2
		exit 1
	fi
	if [ "$output" != $'███' ]; then
		echo "progressbar override precedence mismatch" >&2
		printf 'got: %q\n' "$output" >&2
		exit 1
	fi

	run_progressbar_expect_error none _ $'50\n' \
		'progressbar: COLUMNS or COLUMNS_OVERRIDE unset'

	printf 'progressbar demo checks ok\n'
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

run_bc_tests() {
	local bc_build_dir bc_wasm bc_output

	bc_build_dir="$tmpdir/bc-build"
	if ! bc_wasm=$("$project_root/scripts/build_bc" --out "$bc_build_dir"); then
		echo "build_bc command failed" >&2
		exit 1
	fi
	if [ ! -f "$bc_wasm" ]; then
		echo "build_bc did not produce wasm artefact" >&2
		exit 1
	fi

	bc_output=$(
		printf '2+3\nquit\n' |
			"$wasmrun" --cache "$tmpdir/bc-cache" wasmtime "$bc_wasm"
	)
	bc_output=${bc_output%$'\n'}
	if [ "$bc_output" != "5" ]; then
		printf 'bc wasm result mismatch: %q\n' "$bc_output" >&2
		exit 1
	fi

	printf 'bc wasm build smoke test ok\n'
}

require_helpers
check_inputs

# Ensure quicksort artefact exists at least once before running comparisons.
"$wasmbuild" --cache build "$quicksort_module" >/dev/null

run_quicksort_locale C
run_quicksort_locale en_US.UTF-8

run_ns_override
run_factor_tests
run_progressbar_tests
run_helper_tests
run_bc_tests
