# Giroflée

Lean desktop tool to draw **domestic electrical plans** (plan de position + schéma unifilaire), built with Godot. First country pack: Belgium (RGIE). See [SRD.md](SRD.md) for the full requirements.

Status: milestone M2 done: you can draw walls, doors, windows, stairs, blocks and labels on several étages, with undo, copy/paste, ghost view and autosave. Electric symbols and the unifilaire come next (M3, M4).

## Build and test

Requires **Godot 4.7.2** (pinned).

```bash
GODOT=/path/to/godot tools/run-tests.sh                 # whole test suite, headless
godot --headless --path . -- giroflee-cli version       # headless CLI
godot --headless --path . -- giroflee-cli run-script tests/scenarios/basic_floor.json --print
GODOT=/path/to/godot tools/regen-golden.sh              # regenerate golden files after a deliberate change
godot --path .                                          # start the editor (autosaved project is recovered)
godot --path . -- --open some.giroflee                  # open a project file
```

## Licence

- Code: **GPLv3** ([LICENSE](LICENSE)).
- `packs/` (symbols and data): **CC0** ([packs/LICENSE](packs/LICENSE)).
- **Plans produced with Giroflée belong to you, with no licence conditions attached, commercial use included.**
- **The software comes with no liability for the plans produced with it.** You remain responsible for the accuracy of your drawings; using Giroflée does not guarantee that an inspection will be passed.
