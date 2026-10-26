#!/usr/bin/env bash
# Runs the whole GUT suite headless and fails loudly on anything GUT would only warn about.
#
# GUT silently skips a test script that fails to parse ("Ignoring script ...") and still
# reports success, which would hide tests. This wrapper turns that into a failure.
#
# Usage: GODOT=/path/to/godot tools/run-tests.sh      (GODOT defaults to "godot")
set -uo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if grep -qE "SCRIPT ERROR|Parse Error|Ignoring script|Failed to load script" "$log"; then
	echo "run-tests: a script failed to load (see above); failing the run." >&2
	exit 1
fi
if ! grep -q "All tests passed" "$log"; then
	echo "run-tests: GUT did not report success." >&2
	exit 1
fi
exit "$status"
