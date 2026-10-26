# Giroflée: notes for Claude

Read [SRD.md](SRD.md) first; it is the source of truth. Working agreements are in its section 0. The ones that matter most:

- **Never pick a key or mouse mapping without asking the author.** Only the table in SRD section 7 is approved.
- No personal data in the repo, fixtures or tests. Keep it lean; add things on need.
- Tests travel with the code. Every feature gets unit tests, and a replay test if it involves interaction.

## Commands

```bash
GODOT="/c/Users/LocalAdmin/Desktop/Godot_v4.7.2-stable_win64_console.exe" tools/run-tests.sh
"$GODOT" --headless --path . -- giroflee-cli version
```

Always use `tools/run-tests.sh`, not bare GUT: GUT silently skips a test script that fails to parse and still prints "All tests passed".

## Code rules

- GDScript only, **static typing everywhere**. Untyped declarations and unsafe property/method/cast/call-argument accesses are project **errors**.
  - `int(x)`, `bool(x)`, `float(x)` on a `Variant` are rejected. Assign to a typed variable instead (`var n: float = d.get("k", 0.0)`), or use a typed helper.
  - Loop over untyped arrays with `for item: Variant in arr`.
- Core (`src/core/`) is pure `RefCounted`, no `Node`, headless-testable. UI never mutates the document directly (SRD ARCH-2).
- Tabs for indentation in `.gd` files. French for user-facing strings (via `tr()`), English for code and comments.
- Layout: `src/core` model and logic, `src/cli` headless CLI, `src/ui` scenes, `packs/` data (CC0), `tests/unit`, `tests/integration`, `tests/replays`, `tests/support`.
