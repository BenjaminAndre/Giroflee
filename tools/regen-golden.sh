#!/usr/bin/env bash
# Regenerates the golden project files from the scenario scripts (SRD TEST-4).
# Review the git diff afterwards: that review is the check.
#
# Usage: GODOT=/path/to/godot tools/regen-golden.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

# refresh the global class cache so new scripts are known
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

for script in tests/scenarios/*.json; do
	name="$(basename "$script" .json)"
	"$GODOT" --headless --path . -- giroflee-cli run-script "$script" --out "tests/golden/${name}.giroflee"
done
