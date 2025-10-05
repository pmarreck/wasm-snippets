#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

wasmbuild_path="$project_root/scripts/wasmbuild"
wasmrun_path="$project_root/scripts/wasmrun"
if [ ! -x "$wasmbuild_path" ] || [ ! -x "$wasmrun_path" ]; then
	echo "Bench requires scripts/wasmbuild and scripts/wasmrun" >&2
	exit 1
fi

input_file="data/benchmark/strings.txt"
locale="${LC_ALL:-C}"
runs="${RUNS:-20}"

if [ ! -s "$input_file" ]; then
	echo "Benchmark input $input_file is missing or empty" >&2
	exit 1
fi

mkdir -p build
# Pre-build the module so caches exist before benchmarking.
$wasmbuild_path --cache build wat/quicksort.wat >/dev/null

runners=(
	wasmtime
	wasmedge
	wasmedge-aot
	wasmer
	wasmer-aot
	deno
	wazero
)

available=()
for runner in "${runners[@]}"; do
	case "$runner" in
		wasmedge-aot)
			command -v wasmedge >/dev/null 2>&1 && command -v wasmedgec >/dev/null 2>&1 || continue
			;;
		wasmer-aot)
			command -v wasmer >/dev/null 2>&1 || continue
			;;
		*)
			command -v "$runner" >/dev/null 2>&1 || { echo "Bench: unknown or uninstalled runner $runner" >&2; continue; }
			;;
	esac
	available+=("$runner")
done

if [ "${#available[@]}" -eq 0 ]; then
	echo "No WASM runners available; ensure dev shell is loaded." >&2
	exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

LC_ALL="$locale" LC_COLLATE="$locale" sort "$input_file" > "$tmp_dir/sort.txt"

run_with_wasmrun() {
	local runner="$1"
	local outfile="$2"
	local cache_dir="$3"
	LC_ALL="$locale" LC_COLLATE="$locale" "$wasmrun_path" --cache "$cache_dir" "$runner" wat/quicksort.wat < "$input_file" > "$outfile"
}

successful=()
for runner in "${available[@]}"; do
	cache_dir="build/bench-$runner"
	if run_with_wasmrun "$runner" "$tmp_dir/$runner.txt" "$cache_dir"; then
		if diff -u "$tmp_dir/sort.txt" "$tmp_dir/$runner.txt" >/dev/null; then
			successful+=("$runner")
		else
			echo "Warning: runner $runner produced output differing from sort (LC_ALL=$locale); skipping." >&2
		fi
	else
		echo "Warning: runner $runner failed to execute; skipping." >&2
	fi
done

available=("${successful[@]}")

if [ "${#available[@]}" -eq 0 ]; then
	echo "No WASM runners produced valid output; aborting benchmark." >&2
	exit 1
fi

echo "Running hyperfine with $runs runs per command (LC_ALL=$locale)..."

hyperfine_json="$tmp_dir/hyperfine.json"
hyperfine_args=(
	--warmup 1
	--runs "$runs"
	--export-json "$hyperfine_json"
)

for runner in "${available[@]}"; do
	cache_dir="build/bench-$runner"
	script="$tmp_dir/run-$runner.sh"
	cat > "$script" <<SCRIPT
#!/usr/bin/env sh
LC_ALL=$locale LC_COLLATE=$locale exec "$wasmrun_path" --cache "$cache_dir" "$runner" "$project_root/wat/quicksort.wat" < "$input_file" > /dev/null
SCRIPT
	chmod +x "$script"
	hyperfine_args+=( -n "$runner" "$script" )
done

sort_script="$tmp_dir/run-sort.sh"
cat > "$sort_script" <<SCRIPT
#!/usr/bin/env sh
LC_ALL=$locale LC_COLLATE=$locale exec sort "$input_file" > /dev/null
SCRIPT
chmod +x "$sort_script"
hyperfine_args+=( -n sort "$sort_script" )

hyperfine "${hyperfine_args[@]}"

cp "$hyperfine_json" build/bench-latest.json

HYPERFINE_JSON="$hyperfine_json" python3 <<'PY'
import json
import os
from pathlib import Path

report_path = Path(os.environ['HYPERFINE_JSON'])
if not report_path.exists():
		raise SystemExit

data = json.loads(report_path.read_text())
results = data.get("results", [])
filtered = []
for entry in results:
		name = entry.get("name") or entry.get("command")
		if name == "sort":
				continue
		filtered.append((name, entry.get("mean")))

if not filtered:
		raise SystemExit

filtered.sort(key=lambda item: item[1])
if len(filtered) == 1:
		label, mean = filtered[0]
		print(f"\nIgnoring native sort, fastest WASM runner is {label} ({mean:.3f} s).")
else:
		(best_label, best_mean), (second_label, second_mean) = filtered[:2]
		speedup = (second_mean - best_mean) / second_mean * 100 if second_mean else 0.0
		print(f"\nIgnoring native sort, fastest WASM runner is {best_label} ({best_mean:.3f} s), "
					f"{speedup:.2f}% faster than {second_label}.")
PY

if command -v jq >/dev/null 2>&1; then
	chart_data=$(jq -r '.results | sort_by(.mean)[] | "\((.name // .command))\t\(.mean)"' "$hyperfine_json")
	if [ -n "$chart_data" ]; then
		printf '\nTiming (mean seconds):\n'
		printf '%s\n' "$chart_data" | awk '
			BEGIN { max = 0; scale = 40 }
			{
				split($0, parts, "\t");
				names[NR] = parts[1];
				means[NR] = parts[2] + 0;
				if (means[NR] > max) max = means[NR];
			}
			END {
				for (i = 1; i <= NR; i++) {
					width = (max > 0) ? int((means[i] / max) * scale + 0.5) : 0;
					bar = "";
					for (j = 0; j < width; j++) bar = bar "#";
					printf("  %-14s %8.3f s | %s\n", names[i], means[i], bar);
				}
			}
		'
	fi
fi
