# Changelog

All notable changes to Giroflée. Format inspired by [Keep a Changelog](https://keepachangelog.com/). Every commit that changes behaviour, requirements or tooling adds a line under **Unreleased**; when CI publishes a version, its lines are moved under that version heading.

Versions are `vMAJOR.MINOR.PATCH`: `MAJOR.MINOR` come from the `VERSION` file, `PATCH` is bumped automatically on every build of `main` (SRD section 16).

## [Unreleased]

### Added
- **M1 core** (SRD section 19): document model (project, sheets, entities) with property schemas; command catalogue (`sheet.*`, `entity.*`, `doc.*`, `patch.apply`); patch operations with before/after states and an atomic `PatchApplier`; `Resolver` with sequence numbers and a `committed` signal; `CommandChannel` / `InProcessChannel`; `Session` with transactions and unlimited undo/redo (undo and redo travel as `patch.apply` commands); client-side `IdGenerator` (UUID v4, seedable).
- **Project file** `*.giroflee`: deterministic, git-friendly JSON (`JsonWriter`: sorted keys, `[x, y]` on one line, lossless floats), strict loading, `format_version` 1 with a migration chain that refuses files from newer versions.
- **CLI** `run-script <script.json> [--project] [--out] [--print]`.
- Tests: 134 in total, including golden-file scenarios (`tests/scenarios`, `tests/golden`, `tools/regen-golden.sh`) and seeded property tests that undo/redo through every intermediate state byte for byte.
- `CHANGELOG.md`; SRD draft 0.5 with progress table, working agreement WA-7 (keep this changelog up to date) and implementation notes.

- **M2 canvas and plan editing** (SRD section 19.4): the editor window (étage tabs, canvas, properties panel, status bar, command palette), drawing of walls (mitred, rings without holes), doors and windows that attach to walls and follow them, stairs, grey blocks and text; selection with box, move, vertex and corner handles; snapping to the grid and to wall endpoints and midpoints; copy, cut, paste, duplicate; new, duplicate, rename, delete étage; ghost view; page frame with numbered columns and lettered rows; dot grid and A4/A3 hints; pan and zoom; autosave with silent recovery; open / save as through the palette; `Ctrl+N` opens another window.
- Rendering core: one `DrawList` per sheet (the future SVG/PDF/PNG backends read the same list), `PlanTheme` with the colours measured on the author's plans, `SpatialIndex` (picking 200× faster at 2000 entities).
- Editor logic separated from widgets (`EditorModel`, tools, `EditorInput`), so the whole editor is testable headlessly.
- Tests: 305 in total, including replay tests that drive the real window, a 2000-entity performance check and an opt-in screenshot test (`tests/visual`).

- **M2b: test feedback and look** (SRD section 19.5): previews that look exactly like the finished walls, blocks, openings and stairs; Affinity-style transform box (8 resize handles, rotation handle, Shift / Alt modifiers); smooth diagonal walls (Vulkan "Mobile" renderer with 4x 2D multisampling, measured on screenshots; OpenGL fallback); project-wide display settings (frame, title position, ghost view, A4/A3 hints) with **format 2** and an automatic migration from format 1; menu bar (Fichier, Édition, Étage, Affichage, Projet); icon-only tool bar with hot-key tooltips (hide/show in Affichage, remembered per user); Catppuccin Latte light theme; SVG icon set; Giroflée logo (SVG, PNG, multi-size ICO), splash screen with the Godot logo, window icon.
- Tests: transform handles, project-wide settings and migration, menu bar and tool bar in the real window, theme tokens and contrast, icons, logo at 256 and 32 px, ICO structure, splash; opt-in visual tests for antialiasing and handle/preview screenshots; 2D renderer settings guarded by a unit test.
- `tools/make_branding.gd` regenerates the raster branding assets.

- **M3 electric symbols** (SRD section 19.6): pack and symbol library (Belgium: lamp, switch, two-way switch, socket, TGBT and kWh markers), strict SVG subset parser, symbols drawn at paper size with circuit colours (colour-blind-safe palette); circuits and numbering (next free index, points, "Compacter la numérotation", fresh indices on paste); symbol tools (`L`, `I`, `Shift+I`, `P`), Alt-place, sockets that sit against the wall and face into the room, `C` letter (circuit) and `X` digit (count), pipette (`A`), quickbar (keys 1 to 9, filled from the palette), copy and paste of properties, select by filter, circuit focus (click greys a circuit, double-click isolates it), label solver with draggable pinned labels, anchoring (stacks that move, rotate, copy and delete as one); circuit panel, quickbar strip, symbol tool buttons, "Symboles" menu.
- Tests: 579 in total, including a replayed electrical workflow in the real window.

- **M4 unifilaire** (SRD section 19.7): the unifilaire is a sheet that always exists and is always first, shown as an accent-coloured button left of the étage tabs; étage tabs can be reordered by dragging (and from the palette), new étages go right after the active one; **format 3** adds the unifilaire sheet to older files. The unifilaire is derived from the plans (circuits as columns, points as rows on a shared ruler, switches chained to their lamps, `xN` collapsing, `?` for a switch without lamp, titles proposed from room labels), laid out on the page with the head chain, the bus and its devices, and drawn with the pack artwork. Board editor in the Properties panel (circuit titles, breaker and cable from the pack catalogue, spare circuits, bus devices, head chain, the usual head on request), column and device reordering by dragging, click on a point to see its symbol on the plan. The cartouche is drawn on every sheet from the pack template with project fields edited in the panel. CLI `derive-unifilaire`.
- Tests: 681 in total.

### Changed
- The Windows executable now carries the logo (export preset icon and product details; the release job installs Wine and rcedit).
- `sheet.add`, `sheet.move` and `sheet.remove` keep the unifilaire first and unique; `doc.set` validates `board`, `circuits` and `cartouche`; the status bar zoom is relative to the sheet scale; the golden scenario includes the unifilaire.
- CI: releases are normal releases marked **Latest** (pre-releases can never be "Latest"), with a version-less `Giroflee-windows.zip` asset for a stable latest-download link; a tag pushed by hand (`vX.Y.Z`) builds and publishes that exact version. Existing v0.1.1 to v0.1.3 are untouched.
- CLI: `run-script` moved from "planned" to implemented.
- Schema: the opening property `hinge` was removed (the flips already carry it: DRY); sheets gained `title_pos_mm`; the golden file was regenerated.
- `entity.move` now also moves the openings hosted by a moved wall; `entity.remove` frees the openings of a removed wall.
- Properties of a sheet: the frame, title position, ghost switch and hints moved to the project config (the grey block lost its own corner handles; the transform box replaces them). Wall previews are drawn like finished walls.
- `tests/golden` and `.gutconfig.json`: the default suite runs `tests/unit` and `tests/integration` only; `tests/visual` is opt-in.

## [0.1.1] — M0 scaffold

First automatic release; confirms that the CI pipeline (tests, Windows export, GitHub release) works end to end.

### Added
- Godot 4.7.2 project with strict static typing (untyped declarations and unsafe accesses are errors).
- GUT 9.6.1 test framework, `tools/run-tests.sh` (fails the run when a test script fails to load, which GUT alone would skip silently).
- Headless CLI entry point (`-- giroflee-cli`): `help`, `version`; planned subcommands announced and exit with code 2.
- Replay harness skeleton for "automated gameplay" integration tests (`tests/support/replay_player.gd`, replay JSON format v1).
- GitHub Actions: tests on every push and pull request; automatic Windows release on `main` with an auto-bumped patch version (`VERSION` file holds `MAJOR.MINOR`).
- Windows export preset, GPLv3 licence, CC0 licence for `packs/`, README with the no-liability statement, `third_party/NOTICE`, `CLAUDE.md`.

### Fixed
- CI failed with "Permission denied" on `tools/run-tests.sh`: the workflow now calls it through `bash` and the file is marked executable in git.

## [0.1.0] — Specification

### Added
- Software requirements document (`SRD.md`): vision, domain model, plan editing, modal keyboard model, unifilaire, report, architecture (command/resolver), packs, accessibility, export, licensing, testing, CI.
- Belgian pack rules template (`packs/belgium/rules.template.json`) for the author to fill in.
