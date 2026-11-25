#!/usr/bin/env bash
# Runs the test suites and the benchmarks, keeping your settings and save
# game safe (backed up first, restored afterwards).
#   tests/run.sh              tests + benchmarks
#   tests/run.sh tests        tests only (optionally a filter: tests/run.sh tests galaxy)
#   tests/run.sh bench        benchmarks only
#   tests/run.sh baseline     benchmarks, saved as the new baseline
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
DATA="$HOME/.local/share/godot/app_userdata/Space Atrapos"
BACKUP=$(mktemp -d)
[ -d "$DATA" ] && cp -a "$DATA/." "$BACKUP/"
restore() { if [ -d "$DATA" ]; then find "$DATA" -mindepth 1 -maxdepth 1 ! -name logs -exec rm -rf {} +; cp -a "$BACKUP/." "$DATA/"; fi; rm -rf "$BACKUP"; }
trap restore EXIT
rc=0
mode=${1:-all}
if [ "$mode" = all ] || [ "$mode" = tests ]; then
	"$GODOT" --headless --path . -s tests/run_tests.gd -- "${2:-}" 2>&1 | grep -v "^Godot Engine"
	[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
fi
if [ "$mode" = all ] || [ "$mode" = bench ] || [ "$mode" = baseline ]; then
	extra=""
	[ "$mode" = baseline ] && extra="--save-baseline"
	"$GODOT" --headless --path . -s tests/benchmarks.gd -- $extra 2>&1 | grep -v "^Godot Engine"
	[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
fi
exit $rc
