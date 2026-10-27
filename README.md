# Giroflée

Lean desktop tool to draw **domestic electrical plans** (plan de position + schéma unifilaire), built with Godot. First country pack: Belgium (RGIE). See [SRD.md](SRD.md) for the full requirements.

Status: milestones M2, M2b, M3 and M4 done: you can draw walls, doors, windows, stairs, blocks and labels on several étages (menu bar, tool bar, Affinity-style handles, smooth rendering), then place lamps, switches and sockets on numbered circuits (Alt-place, pipette, quickbar, circuit focus, stacks), with undo, copy/paste, ghost view and autosave. The unifilaire tab is derived from the plans, with its board (head chain, bus, circuit order) and the cartouche editable; the report and rules come next (M5).

## Build and test

Requires **Godot 4.7.2** (pinned).

```bash
GODOT=/path/to/godot tools/run-tests.sh                 # whole test suite, headless
godot --headless --path . -- giroflee-cli version       # headless CLI
godot --headless --path . -- giroflee-cli run-script tests/scenarios/basic_floor.json --print
GODOT=/path/to/godot tools/regen-golden.sh              # regenerate golden files after a deliberate change
godot --path .                                          # start the editor (autosaved project is recovered)
godot --path . -- --open some.giroflee                  # open a project file
godot --headless --path . -s tools/make_branding.gd      # regenerate icon.png, icon.ico, splash.png from the SVG logos
```

## Licence

- Code: **GPLv3** ([LICENSE](LICENSE)).
- `packs/` (symbols and data): **CC0** ([packs/LICENSE](packs/LICENSE)).
- **Plans produced with Giroflée belong to you, with no licence conditions attached, commercial use included.**
- **The software comes with no liability for the plans produced with it.** You remain responsible for the accuracy of your drawings; using Giroflée does not guarantee that an inspection will be passed.
