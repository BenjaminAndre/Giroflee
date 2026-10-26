# Giroflée: notes for Claude

Read [SRD.md](SRD.md) first; it is the source of truth. Working agreements are in its section 0. The ones that matter most:

- **Never pick a key or mouse mapping without asking the author.** Only the table in SRD section 7 is approved.
- No personal data in the repo, fixtures or tests. Keep it lean; add things on need.
- Tests travel with the code. Every feature gets unit tests, and a replay test if it involves interaction.
- **Keep `CHANGELOG.md` up to date with every commit** (entry under *Unreleased*), and keep the SRD progress table (section 0.1) in sync.

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
- Tests: GUT asserts take untyped arguments, so test scripts that pass dictionary lookups to them start with `@warning_ignore_start("unsafe_call_argument")`. Helpers in `tests/support/` must not start with `test_` (GUT would collect them). After adding a `class_name`, run `godot --headless --path . --import` (the tool scripts do).
- Golden files: after a deliberate change to the file format or to a scenario, run `tools/regen-golden.sh` and review the diff.
- Core (`src/core/`) is pure `RefCounted`, no `Node`, headless-testable. UI never mutates the document directly (SRD ARCH-2).
- Tabs for indentation in `.gd` files. French for user-facing strings (via `tr()`), English for code and comments.
- Layout: `src/core` model, commands, rendering (`render/`) and geometry (`geometry/`); `src/editor` editor logic without widgets (model, tools, input routing, palette); `src/cli` headless CLI; `src/ui` widgets; `packs/` data (CC0); `tests/unit`, `tests/integration` (real window, replayed input), `tests/visual` (opt-in screenshots), `tests/replays`, `tests/support` (`TestKit`, `EditorKit`, `UiHarness`, `ReplayPlayer`).
- UI code never mutates the document: widgets call `EditorModel`, which goes through the `Session` (commands). Editor behaviour is tested through `EditorKit` / `UiHarness`, not by poking widgets.
- Look: the interface is **light only** (Catppuccin Latte). Colours come from `AppTheme` constants, never ad hoc; tool icons are SVG files in `assets/icons/` loaded through `IconLibrary`; menu items show shortcuts as text only (no `Shortcut` resource, the editor's key handling is the single place where keys are interpreted). Project-wide display settings live in the project `config`, not on sheets.
- Rendering: the project uses the Vulkan "Mobile" renderer with 4x 2D multisampling (the Compatibility renderer cannot multisample 2D). Previews must be drawn by the same code as the finished object (SRD FR-PREV). Visual checks live in `tests/visual` (opt-in, need a display).
- Key bindings: only the ones approved in SRD section 7; anything the SRD marks ASSUMED is listed in section 18 for the author to confirm.
