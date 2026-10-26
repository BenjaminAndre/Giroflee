# Giroflée — Software Requirements Document

Status: **draft 0.3** · Language of this document: English · Language of the product: French (v0.1)
Audience: the author, and Claude (as the implementing agent). Technical notes are mixed in on purpose and marked **[TECH]**. Requirements are numbered so code, tests and commits can cite them (`FR-…`, `ARCH-…`, `PACK-…`, `LIC-…`).

Keywords: MUST / SHOULD / MAY as in RFC 2119. Everything here has been decided by the author unless it appears in the pending list of section 18.

---

## 0. Working agreements with the implementing agent

- **WA-1** **Never choose a key or mouse mapping without asking the author.** The only approved mappings are the ones in section 7 and FR-PLAN-2. Anything else is a proposal until confirmed.
- **WA-2** **Keep it lean.** Add features and catalogue entries when they are needed, not because they "may be needed". No decoration libraries.
- **WA-3** **DRY** (see principle in section 1): when information already exists somewhere, derive it; do not ask the user to type it twice, and do not duplicate it in the data model.
- **WA-4** No personal data of the author or of real clients in the repository, fixtures, tests, screenshots or examples. Use fictitious data.
- **WA-5** If a requirement is ambiguous, ask. Do not fill the gap silently.
- **WA-6** **Tests travel with the code.** Every feature lands with unit tests, and with an integration (scenario/replay) test when it involves user interaction; every fixed bug lands with a regression test (section 15.3). CI must stay green.

---

## 1. Vision

Giroflée is a desktop tool to draw **domestic electrical plans**:

1. the **plan de position** (symbols on the floor plans, one sheet per **étage**), and
2. the **schéma unifilaire** (single-line diagram), **computed from the plan** wherever it can be, and editable where it cannot.

It is essentially a focused vector editor ("a glorified SVG editor") with a curated symbol set, a keyboard-first workflow, and a rule engine configurable per country. The first country pack is **Belgium (RGIE)**.

**Why it exists.** Existing professional software is bloated for a domestic installation, and general drawing software (Affinity) works but is slow: the author needed about 5 h for a full set of plans for their own house.

**Success criterion.** The author draws the plans of a comparable house (their mother's house, spring 2027) in **under 1 hour**, with the unifilaire generated rather than drawn.

**Design principles**

- **The plan is the source of truth.** Everything that can be derived from it (the unifilaire rows, point counts, labels, the report) is derived, never typed again. *This is to avoid entering the same information twice. DRY (Don't Repeat Yourself), as in code.* The same principle applies inside the plan: the floor name is typed once and appears on the tab, the sheet and the cartouche; a project-wide font is set once; a symbol's artwork is defined once and reused by every instance.
- **Lean.** A few important elements instead of hundreds of decorations. A feature that does not make plan drawing faster is rejected by default.
- **Keyboard first, mouse friendly.** Modal, vim-like shortcuts, command palette (a little Factorio-like in feel: pipette, fast repeat).
- **No dialogs.** Sane defaults, everything changeable at any time from docked panels. The only mandatory popup is the export disclaimer (FR-LEG-1).
- **Clear, accessible output.** Readable by everyone, including colour-blind and dyslexic users.
- **Honest.** The tool assists. The author of a drawing remains responsible for its accuracy.

## 2. Users, context, legal

- **Primary user:** the author (DIY on their own and relatives' houses; occasional professional use).
- **Secondary:** other home owners and installers drawing domestic installations; newcomers who benefit from the optional rule report.
- **Acceptance by inspector.** Exported plans MUST be acceptable to a Vinçotte inspector (non-negotiable). The Belgian pack's output (symbols, labelling, cartouche content, unifilaire content) is validated by the author against what the inspector expects. The software does not claim compliance.
- **Derogations exist** (older houses may get accommodations from the inspection body, as written in the RGIE). Therefore rules are **advisory**: exceeding a limit is a warning, never a block (see FR-RPT).
- **FR-LEG-1** Every export (SVG, PDF, PNG) MUST show a reminder popup: the user is responsible for the truthfulness of the drawing; using the software does not guarantee that an inspection will be passed; the software carries no liability for the plans produced with it. One confirm button. It is the only modal dialog in the app and it is **not suppressible**: no setting, no "don't show again", no command-line flag. (Anyone who really wants to remove it can recompile the software; the author does not take liability for that.)
- **FR-LEG-2** The software is under **GPLv3**; exported documents carry no licence condition (section 14).
- Target regulation for v0.1: **RGIE** (Belgium). Rule thresholds live in data and are **not hard-coded**. The author transcribes them from the official text into `rules.json` (template provided, section 11.4).

## 3. Scope by version

| Version | Contents |
|---|---|
| **v0.1** | Everything in sections 5–13 unless marked otherwise. Windows target. |
| **v0.2** | "Glued A4" long unifilaire (the scene grows to N sheets side by side, printed in tiles to be glued together). Probably needed for large installations. |
| **v0.3** | Sub-boards (tableaux divisionnaires). |
| **Later** | More symbols and catalogue entries, added **on need**; more packs; Linux/Arch packaging (the build must stay portable from day one). |
| **Maybe later** | Cable routes, lengths, budget / bill of materials (also useful for inspecting old installations); **multiplayer** (the architecture MUST stay compatible, section 10); three-phase, PV, EV charger, heat-pump specifics. |

**Non-goals for v0.1:** architectural accuracy (plans need not be to scale), decoration libraries, 3D, cable routing, budgeting, networking, languages other than French.

## 4. Glossary (French terms that appear in the UI)

| Term | Meaning |
|---|---|
| Plan de position | Floor plan with symbols |
| Schéma unifilaire | Single-line diagram of the installation |
| **Étage** | A floor of the building. **Named, not numbered** (e.g. "Cave", "Rez", "+1", "Grenier"). One plan sheet per étage, shown as a tab |
| Circuit / ligne | An electrical circuit, identified by a letter (A, B, C…) |
| Indice / repère | Number of a point inside a circuit (A1, A2…) |
| Point (électrique) | A group sharing the same circuit and index, counted once by the rules (e.g. a triple socket = 1 point) |
| Empilement | A stack of symbols at one wall spot (socket low, switch at waist, lamp high). Created by **anchoring** a symbol to another; it then moves as one (FR-STACK) |
| Ancrage | Relative attachment of a symbol to another symbol |
| Barre rapide | Quickbar: 9 slots (keys 1–9) holding tool presets (FR-QB) |
| Focus (circuit) | View state that greys out or solos circuits (FR-FOCUS) |
| TGBT | Main board (tableau général basse tension) |
| Différentiel | RCD / residual-current device |
| Cartouche | Title block at the bottom of a sheet |
| Cadre / repérage | Border frame with columns (1…n) and rows (A…n) |
| Pack | Country bundle: symbols, rules, catalogue, cartouche template |

## 5. Domain model

All entities have a UUID, are plain data, and live in a **Document**.

**Coordinates (ARCH-C):** integer millimetres in real-world units (**[TECH]** `Vector2i`; keeps commands deterministic and JSON lossless). **Math axes: x points right, y points up**; angles are counter-clockwise positive. There is no north: the drawing need not be north-aligned and nothing in the app assumes it. The y-flip happens only at the output boundaries (screen canvas, SVG, PDF, PNG). Core never sees y-down. Page-space items (frame, cartouche) are laid out in Core with the same convention; the frame rows are lettered A… from the visually top row.

```
Project
 ├─ config            (project-wide settings, changeable any time, undoable: fonts, grid, frame…)
 ├─ pack_ref          (e.g. "belgium" + version)
 ├─ cartouche         (template + field values)
 ├─ board             (head chain + bus + circuit order; section 8)
 ├─ circuits[]        (letter, colour, title, breaker, cable, …)
 ├─ symbol_defs[]     (project-specific custom symbols; section 6.4)
 └─ sheets[]          (ordered; each a tab)
     ├─ kind: "plan" | "unifilaire"
     ├─ name              (étage name; the single source of the name, DRY)
     ├─ paper (size, orientation), scale, grid, frame (cols, rows), ghost (which étages), hints
     ├─ background (image/PDF ref, transform, opacity)  [plan only]
     └─ entities[]
          Wall · Opening(door|window) · Stair · GreyBlock · TextLabel · ElectricSymbol
```

### 5.1 Entities (plan sheets)

| Entity | Properties | Notes |
|---|---|---|
| **Wall** | polyline points, line weight | Thick black stroke whose **weight is a page weight in mm** (default ≈ 1.4 mm), so it looks the same at any scale; it is not a world size. Corner joins (mitre) and T-junctions look clean. One default weight, per-wall override. The wall's geometry is its centreline. |
| **Opening** (door / window) | width, hinge side, swing, flip H/V, optional `host_wall` + offset | Parametric. Snaps to walls and moves with its host wall. Rendered as grey swing sector (door) or grey rectangle (window). The wall is **not** cut. |
| **Stair** | width, step count, tread, rotation, flip | Parametric. Ladder look. |
| **GreyBlock** | rectangle (resizable), rotation | Light grey, semi-transparent so the dot grid shows through. Stands for furniture, bathtub, a garage zone… The only generic decoration. |
| **TextLabel** | text, rotation, role, optional font / size override | Free text: room names (blue), "Rue" / "Jardin", etc. Editable everywhere. |
| **ElectricSymbol** | `type`, `circuit`, `index`, `count` (default 1), position, rotation, flip, label offset, count-badge offset, optional `height`, optional `anchor` (`parent_id` + relative offset) | See section 6. `height` (above floor, mm) is optional metadata for later rule checks. `anchor` makes a stack (FR-STACK). |

The **étage name** is shown automatically as a large dark-red title on the sheet (default top right, repositionable), as the tab title, and as `{sheet.name}` in the cartouche. It is typed once.

### 5.2 Circuit and point identity

- A symbol carries `circuit` (letter A–Z) and `index` (integer ≥ 1). Its main label is `<circuit><index>` (e.g. `A2`). The label is **a property of the symbol**, so orphan labels cannot exist.
- All symbols of the same circuit sharing the same `index` form **one point / group**, across all sheets. This is how a switch and its lamp(s) are linked.
- `count = N` means N identical items drawn as one symbol (a triple socket is `count 3`). It is shown as a separate **`xN` badge**, positioned **away from the circuit label** (default: the opposite side of the symbol from the label, never adjacent to it, to avoid confusion with the letter naming). It has its own offset, draggable, and is included in collision solving (FR-SYM-5). Rules count one point per group, so a triple socket counts once (a per-country rule in the pack).
- Circuit letters: A–Z in v0.1.

## 6. Plan-sheet editing (FR-PLAN)

### 6.1 Canvas
- **FR-PLAN-1** Infinite canvas with dot grid and snapping (grid, wall endpoints/midpoints, wall faces). Faint **hints for the A4 and A3 page borders** (dashed outlines at the sheet's current scale, anchored to the sheet's paper origin) so the user sees what will fit; togglable. Grid step and snap are configurable at any time.
- **FR-PLAN-2** Navigation like Affinity: wheel = vertical pan, Shift+wheel = horizontal pan, Ctrl+wheel = zoom at cursor, Space+drag and middle-drag = pan. All remappable.
- **FR-PLAN-3** Walls: polyline tool, grid/object snapping, live length readout, orthogonal by default, Shift for free angle.
- **FR-PLAN-4** Door, window, stair are parametric. `H` flips horizontally, `V` flips vertically (also during placement), `R` rotates, `Shift+R` rotates the other way.
- **FR-PLAN-5** Plans can be drawn **by hand on the blank grid**, no import and no scale accuracy required, in minutes.
- **FR-PLAN-6** Background import: image (PNG/JPG) and PDF page, as a locked, adjustable-opacity layer with two-point scale calibration; excluded from export unless the user opts in. **[TECH]** PDF import may follow images inside v0.1 if Godot has no built-in PDF rasteriser.
- **FR-PLAN-7** **Ghost view**: shows other étages in light grey on the current sheet. Togglable per sheet, **off by default**, and configurable to show **any** étage (one or several). Étages are *named*, not numbered, and have no assumed vertical order (real houses are wonkier than −1/0/+1/+2); the tab order is whatever the user sets. Never exported.
- **FR-PLAN-8** Border frame: configurable columns and rows. A count of **0 removes the frame on that axis**. Cosmetic by default; usable as a position reference in the report.
- **FR-PLAN-9** Paper: any size and orientation can be set at any time; default A-series landscape (A3). The plan lives in real-world mm; the frame and cartouche scale with the page. Retargeting the page size at export (A4, A3, …) applies a uniform scale.
- **FR-PLAN-10** Objects outside the paper rectangle raise a warning (they would be cut at export).

### 6.2 Electric symbols
- **FR-SYM-1** v0.1 symbol set (Belgian pack): **interrupteur**, **interrupteur va-et-vient**, **lampe**, **prise**, plus the **TGBT** and **compteur kWh** markers (shown in green on the plan).
- **FR-SYM-2** Placement by tool key, repeatable (stay in the tool until Esc). A symbol gets the **active circuit** and the **next free index** automatically.
- **FR-SYM-3** **Alt-place**: placing with Alt held reuses the previous index (links the new symbol to the same point). Workflow: place a lamp, then Alt-place its switches, release Alt, place the next lamp (new index), etc.
- **FR-SYM-4** **Wall orientation**: a socket auto-rotates on placement to face away from the nearest wall within a snap distance, back against the wall's drawn edge, i.e. the centreline offset by half the wall's page weight at the sheet scale (preview before click). Manual rotation (`R`) overrides and sticks.
- **FR-SYM-5** **Label placement with basic collision solving.** On placement or move, the circuit label and the `xN` badge are placed by scoring candidate positions around the symbol (e.g. 8 directions): a symbol near a wall gets its labels **away from the wall**; when several symbols are **stacked or close together**, labels go to a **free side** (avoiding other labels, symbols and walls). A label the user has dragged is pinned and never moved by the solver. No global optimisation in v0.1.
- **FR-SYM-6** `count` is editable in the Properties panel and by shortcut: `X` then a digit (e.g. `X` `3`).
- **FR-SYM-7** Changing a symbol's circuit: select (click or box), then `C` + letter (e.g. `C` `H`). With nothing selected, `C` + letter sets the **active circuit**. Reassigned symbols take the next free index in the new circuit (links inside the moved selection are preserved).
- **FR-SYM-8** Renumbering: palette command **"Compacter la numérotation"** removes gaps in a circuit's indices (or all circuits). No default key. Deleting never renumbers automatically (stable indices).
- **FR-SYM-9** **Pipette** (`A`, like Factorio's Q): over an entity, switches to the tool for that entity type, with its properties (symbol type, flip, rotation, count; opening/stair parameters; wall weight) and, for an electric symbol, the **active circuit** set to its circuit. Alt-placing right after reuses that symbol's index. Circuit-focused-out items (FR-FOCUS-1) are not picked.

### 6.3 Stacks (FR-STACK)
Real walls often hold a vertical stack at one spot: a socket near the floor, a switch at waist height, a lamp at head height. On a plan these are drawn side by side.
- **FR-STACK-1** **Anchoring a symbol to another symbol makes a stack.** There is no separate stack object: a symbol may have one `anchor` (parent symbol + relative offset); a stack is a parent with its anchored descendants. Chains are allowed, cycles are rejected by the Resolver. Moving, rotating or flipping a parent carries all its descendants (rotation/flip act on the offsets too). Moving an anchored symbol on its own only changes its offset. Circuits, indices and labels stay per symbol.
- **FR-STACK-2** Commands (command palette): **"Ancrer à un symbole"** (pick the parent) and **"Détacher"**. Detaching, or deleting the parent, leaves the children in place at their current absolute position and unanchored. Any dedicated key or mouse gesture is added only when the author asks (WA-1).
- **FR-STACK-3** Copy and cut of a symbol include its descendants; pasting recreates the anchoring. Copying an anchored child alone drops the anchor.
- **FR-STACK-4** The label solver (FR-SYM-5) treats a stack as one unit and fans the labels out on a free side.
- **FR-STACK-5** The tool does **not** create or enforce the physical order of a stack (not its responsibility). Each symbol may carry an optional `height`; a later rule MAY validate heights against the RGIE (not in v0.1).

### 6.4 Selection, editing, copy/paste (FR-EDIT)
- **FR-EDIT-1** Click, Shift-click, box select; select-all; delete; move with snapping; arrow-key nudge.
- **FR-EDIT-2** Copy / cut / paste of any selection (walls, openings, stairs, blocks, labels, symbols, stacks), **between sheets, projects and app windows**. **[TECH]** system clipboard as JSON text with a `giroflee/1` header.
- **FR-EDIT-3** Paste of electric symbols: each pasted point group gets **fresh indices** in its circuit while **keeping its internal links** (a pasted switch+lamp pair stays a pair). Paste position: at cursor.
- **FR-EDIT-4** **Duplicate étage** (palette command, plus a key): copies the architectural content (walls, openings, stairs, blocks, labels) **without** electric symbols. A second command, "Dupliquer l'étage avec les symboles", copies everything (indices reassigned as in FR-EDIT-3). The author's workflow: map the ground floor → duplicate → adjust walls/doors → copy symbols from another étage.
- **FR-EDIT-5** Unlimited undo/redo; a drag or a multi-object operation is one step (**[TECH]** command transactions).
- **FR-EDIT-6** All text is editable in place: room labels, symbol labels, étage name, cartouche fields.
- **FR-EDIT-7** **Copy / paste settings** (like Factorio's copy settings): copy the *style-like* properties of one entity and apply them to a selection of entities **of the same type** (others are ignored). Copied: text font, size and role; symbol flip, count and rotation; opening and stair parameters; wall weight; grey-block fill. Never copied: identity, position, circuit, index, anchor. Commands "Copier les propriétés" / "Coller les propriétés" in the palette; no key or gesture is assigned until the author picks one (WA-1).
- **FR-EDIT-8** **Select by filter**, as palette commands acting on the current étage: "Sélectionner tout le circuit …", "Sélectionner tous les symboles de type …" (prises, lampes, interrupteurs…), "Sélectionner les textes à police ou taille personnalisée" (FR-TXT-3), "Sélectionner les symboles sans circuit". More filters are added on need.

### 6.4b Quickbar and circuit focus

- **FR-QB-1** **Quickbar**: 9 slots, activated by the keys **1–9**. A slot holds a **tool preset**: a tool plus its properties (e.g. "lampe", "prise count 3", "porte 800 mm", "mur de poids 2 mm"). The active circuit is not part of a preset (it stays under the author's control with `C`).
- **FR-QB-2** The quickbar is displayed on screen (numbered slots, current one highlighted). A preset is shown with its symbol/tool icon.
- **FR-QB-3** How slots are filled, and whether the quickbar belongs to the project or to the user: **undecided**, section 18 (WA-1).
- **FR-FOCUS-1** **Circuit focus** lives in the side panel that already lists the circuits with their colours. A **click** on a circuit greys it out (out of focus: its symbols are drawn light grey, are not box-selectable and are not picked by the pipette; they stay visible). A second click restores it.
- **FR-FOCUS-2** **Double-click** a circuit = **solo**: every other circuit is greyed out. Double-clicking the solo circuit again **restores the visibility state from before the solo**.
- **FR-FOCUS-3** Focus is **view state** (per window, not in the Document, not exported, not undoable; ARCH-7). Walls, openings and labels are never affected by it.

### 6.5 Custom symbols
- **FR-CSYM-1** The user can import their own SVG and register it as a project-specific symbol, mapped onto a **base type** (lamp, switch, socket, generic point) so rules and the unifilaire know how it behaves.
- **FR-CSYM-2** **Global resize**: each symbol type has one project-wide scale; changing it resizes every instance everywhere. No per-instance scale in v0.1.
- **FR-CSYM-3** The importer validates against the supported SVG subset (section 11.3) and reports problems in the report panel.
- **FR-CSYM-4** A symbol has two artworks: `plan` and `unifilaire` (they look different). If the unifilaire artwork is missing, fall back to the plan artwork with a warning.

### 6.6 Text and fonts (FR-TXT)
- **FR-TXT-1** **Project-wide font and size**: one font family and one base size for all plan text, changeable at any time from the Properties panel with no popup. Default font **Atkinson Hyperlegible**; **OpenDyslexic** selectable; both SIL OFL (licence texts shipped). The UI font is a separate setting.
- **FR-TXT-2** Text roles (room label, symbol label, count badge, étage title, cartouche) have a default size factor relative to the base size, defined by the theme.
- **FR-TXT-3** **Node-by-node override** of font family and size on any text, with a "reset to project" command. (Avoids the Affinity pain of text that can only be fixed one object at a time: a project-wide change reaches every non-overridden text, and a command selects all overridden texts.)
- **FR-TXT-4** Sizes are in **paper points**, so text stays legible at any export page size; it does not scale with the world scale.

### 6.7 Cartouche (title block)
- **FR-CART-1** Template from the pack (layout: *Adresse installation, Propriétaire, Installateur, Organisme de contrôle, Date, Signature*), editable per project **in place**: a cell grid with draggable row/column sizes, editable texts, addable/removable cells.
- **FR-CART-2** Cells may contain variables (`{project.address}`, `{sheet.name}`, `{page}`, `{date}`); project-level values are entered once and shared across sheets.
- **FR-CART-3** The cartouche appears on every sheet, unifilaire included.

## 7. Modal keyboard model (FR-KEY)

Vim-like: a **Normal** mode (select) and tool states. `Esc` always returns to Select. All bindings are data (`keymap.json`) and remappable. **These are the approved defaults.** Per WA-1, nothing outside this table may be added without asking.

| Key | Action |
|---|---|
| `Esc` | Select tool / cancel |
| `W` | Wall |
| `D` | Door |
| `F` | Window (fenêtre) |
| `E` | Stair (escalier) |
| `S` | Grey block (square) |
| `T` | Text |
| `L` | Lampe |
| `I` | Interrupteur |
| `Shift+I` | Interrupteur va-et-vient |
| `P` | Prise |
| `A` | **Pipette**: switch to the tool of the item under the cursor (FR-SYM-9) |
| `1`–`9` | **Quickbar** slots (FR-QB) |
| `C` then letter | Circuit: sets the active circuit, or reassigns the selection (FR-SYM-7) |
| `X` then digit | Set `count` (FR-SYM-6) |
| `H` / `V` | Flip horizontally / vertically |
| `R` / `Shift+R` | Rotate one way / the other (R: clockwise on screen) |
| `Alt` while placing | Reuse previous index |
| `Ctrl+N` | New project (in a **new window**) |
| `Ctrl+T` | New étage tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |
| `Ctrl+P` | Command palette (fuzzy search) |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo |
| `Ctrl+C/X/V`, `Ctrl+D` | Copy / cut / paste, duplicate selection |
| `Tab` / `Enter` | In the report panel: next issue / acknowledge |
| `F2` | Edit text of the selection |

- **FR-KEY-1** Command palette: fuzzy search over **every** command (French names, e.g. "Compacter la numérotation", "Dupliquer l'étage", "Exporter en SVG", "Afficher l'étage fantôme"); each shows its shortcut when one exists.
- **FR-KEY-2** `C` enters a short-lived circuit-picker state that shows the available letters on screen.

### 7.1 No-dialog configuration (FR-CFG)
- **FR-CFG-1** No settings dialog, no startup wizard. Defaults are sane. A docked, context-sensitive **Properties panel**: with nothing selected it shows sheet/project settings (paper, scale, grid, frame, hints, ghost, fonts, cartouche fields); with a selection it shows that entity's properties. Every change is a command (undoable).
- **FR-CFG-2** **One project per window; the tabs of a window are the étages of that project** (plus the unifilaire tab). `Ctrl+N` opens another window. **Autosave and silent recovery** at next launch replace any "save changes?" dialog.

## 8. The unifilaire (FR-UNI)

The unifilaire is a **sheet kind** whose content is the sum of **computed** and **user-edited** parts.

### 8.1 Computed (never hand-edited; always regenerated from the plans)
- For each circuit, the **rows** are its points (groups), ordered by index. Each row shows the symbols of its group in the unifilaire artwork (switch(es) → lamp(s) chained; sockets collapsed with `xN`).
- A group with a switch but no consumer renders `?` and raises an **error** (FR-RPT).
- The **row ruler** (1…n) is shared by all columns and runs to `max(pack's max-points, highest index used in any circuit)`. It is **not capped**: older installations may legitimately exceed the usual limit (derogation); the excess is flagged as a warning only, never prevented.

### 8.2 Editable (cannot be derived from plans)
- **Circuit order** (column position) and **circuit title** (the "line label" above the column), proposed from nearby room labels (most frequent nearest labels among the circuit's symbols, max 2), editable.
- **Per-circuit protection**: breaker rating/curve/breaking capacity, cable type and section. Defaults come from the pack; defaulted values are flagged (FR-RPT).
- **Board topology**: the **head chain** (e.g. meter → differential → cable → main breaker) and the **bus**: an ordered sequence of circuits and devices (e.g. a 30 mA differential) along which circuits are tapped. A device on the bus protects the circuits farther from the **feed point** (where the head chain enters the bus). This matches the common layout where some circuits sit behind a 30 mA differential and the others are protected only by the upstream one.
- Head chain and bus items are picked from the pack's **catalogue** (section 11.5). **Not auto-generated** (this is the real electrical design work).
- Spare circuits (empty columns) MUST be supported.
- **v0.3:** sub-boards. **v0.2:** multi-A4 long unifilaire. In v0.1 the sheet is a single page; if the content does not fit, scale-to-fit with a warning.

### 8.3 Editing UX
- **FR-UNI-1** The computed part is read-only on the canvas (clicking jumps to the source symbol on its plan). The editable part is edited via the Properties panel and direct manipulation (drag a column to reorder, click a device to edit).
- **FR-UNI-2** Everything the user edits survives regeneration, keyed by circuit letter / device UUID.

## 9. Report / validation view (FR-RPT)

- **FR-RPT-1** A docked panel listing issues. **Entirely optional**: the app never blocks on it, and **exports are never blocked**. It helps newcomers and catches mistakes; derogations are a reality.
- **FR-RPT-2** Two severities, defined by the author:
  - **Error** = missing data: the plan will certainly be refused by an inspector (e.g. symbol without circuit, switch without any consumer, no head chain, required cartouche fields empty: address, owner, installer; not date/signature).
  - **Warning** = something the tool cannot guarantee, or a defaulted value (e.g. 9 points in a circuit, which may be acceptable in an old house; defaulted breaker rating; objects outside the page; a bathroom check on a plan that may not be to scale).
- **FR-RPT-3** `Tab` moves to the next issue (the canvas centres on its subject), `Enter` acknowledges it. Acknowledged issues are stored in the project with a key (rule id + subject ids + hash of relevant data) and **reappear if the underlying data changes**. Goal: validate an auto-generated unifilaire with a dozen Tab+Enter in under a minute.
- **FR-RPT-4** Rule set v0.1 (Belgian pack, all data-driven; thresholds from `rules.json`):
  - max points per circuit (warning), counted per group
  - symbol without circuit (error)
  - switch group without consumer (error); consumer group without any switch (warning)
  - circuit without breaker or cable (defaulted → warning)
  - breaker vs cable-section compatibility (table in pack)
  - circuits not behind a 30 mA differential where required (warning)
  - missing or incomplete head chain (error)
  - bathroom proximity check (warning): heuristic from room labels matching pack keywords and nearby symbols; the message states that the plan may not be to scale
  - cartouche required fields empty (error)
  - objects outside page (warning)
- **FR-RPT-5** When an export is made with open errors, a **"PROVISOIRE" mark** is added **in the cartouche area**, cleanly **not touching any border or line**, as its own SVG group (`id="provisoire"`) so that someone unhappy with it can delete it in Affinity or Inkscape. On by default; the setting is changeable at any time.

## 10. Architecture (ARCH) **[TECH]**

### 10.1 Goals
Low coupling. Every change to the document is a serializable **command**; one component (the **Resolver**) is the only writer. That makes undo/redo, scripting, tests and a future multiplayer server nearly free.

### 10.2 Layers

```
 ┌───────────────────────────── UI (Godot scenes, Control/Node2D) ─────────────────────────────┐
 │ Canvas · Tools · Panels · Command palette · Tabs · Input/keymap                             │
 └───────────────┬───────────────────────────────────────────────────▲─────────────────────────┘
        submits  │ Command                                           │ signals: committed(patch)
 ┌───────────────▼───────────────────────────────────────────────────┴─────────────────────────┐
 │ Session client:  CommandChannel (interface) ──► in-process Resolver (v0.1) ──► Document     │
 │ History (inverse commands, transactions) · Selection · Active circuit · Viewport (not doc)  │
 └───────────────┬─────────────────────────────────────────────────────────────────────────────┘
                 │ reads (immutable snapshot / queries)
 ┌───────────────▼─────────────────────────────────────────────────────────────────────────────┐
 │ Core (pure GDScript, RefCounted only, no Node, headless-testable)                           │
 │ Document model · Commands · Derivations (unifilaire builder, numbering) · Rule engine       │
 │ Geometry/snapping/label solver · Pack loader · Scene→DrawList renderer · Exporters          │
 └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **ARCH-1** Core MUST NOT depend on the scene tree. It MUST run headless (`godot --headless`) for tests and CI.
- **ARCH-2** The UI MUST NOT mutate the Document directly. All mutations: `Command` → `CommandChannel.submit()` → `Resolver` → `committed(patch)` signal. The UI re-renders from patches.
- **ARCH-3** **Command** = `{ id: UUID, type: String, payload: Dictionary of JSON primitives, tx: gesture id, author: String }`. All IDs (entities, commands) are generated **by the client before submission**. `apply()` MUST be deterministic: no randomness, clock or global state inside it.
- **ARCH-4** The Resolver validates a command against the current Document, applies it, assigns a monotonically increasing `seq`, and emits a **patch** (entity add/update/remove ops with before/after, enough to invert).
- **ARCH-5** **Undo** = client-side history of inverse commands, submitted as new commands (so it works unchanged with a remote resolver). Gestures are grouped by `tx`.
- **ARCH-6** `CommandChannel` is an interface. v0.1 ships `InProcessChannel` (synchronous). A network channel is out of scope, but nothing in Core may assume the Resolver is local or synchronous (the UI must tolerate a delayed `committed`).
- **ARCH-7** **Not in the Document and not commands:** selection, hover, viewport, active circuit, circuit focus (greyed/solo), open tab, tool state. These are per-user UI state. (The active tab and viewport MAY be persisted in an optional `ui` block of the file; the Resolver ignores it.)
- **ARCH-8** **Derived data is never stored or transmitted as truth** (DRY): unifilaire rows, report, point counts, label proposals are recomputed from the Document (cached by `seq`). Only user overrides and acknowledgements are stored.
- **ARCH-9** **Config is document state:** project settings (frame, grid, fonts, symbol scales…) change through commands, so they are undoable and syncable.
- **ARCH-10** The command stream is the scripting API: any automation is a JSON list of commands. A **headless CLI mode** is **required** (it underpins unit and integration tests): `godot --headless -- giroflee-cli <subcommand>` with at least `run-script <commands.json> [--project <file>]` (apply commands, save result), `export-svg <project> <out>`, `derive-unifilaire <project>` (print the derived diagram as JSON) and `validate <project>` (print the report as JSON). Exit codes are non-zero on failure.
- **ARCH-11** Anchoring/stacks, groups, indices, numbering, quickbar presets, copy-settings and label placement are Core logic with unit tests, not UI code.

### 10.3 Rendering, one drawing pass **[TECH]**
- **ARCH-12** A single pure function `Renderer.build(document, sheet, view_options) → DrawList` produces backend-agnostic primitives (polyline, polygon, arc, circle, rect, text, `symbol_ref(id, transform)`, group, clip). Backends consume the same DrawList: **Canvas** (screen), **SVG**, **PDF**, **PNG** (SubViewport). This guarantees on-screen = exported. The y-flip lives in the backends.
- **ARCH-13** Screen backend: custom canvas on `Node2D` + `_draw()` (decided; **not** `GraphEdit`), with its own picking, snapping, selection. Symbols on screen come from SVG rasterised at a zoom-dependent scale and cached (or the engine's resolution-independent SVG texture, if the pinned version has one). Exports always use the original vector data.
- **ARCH-14** Hit-testing and snapping in Core on integer geometry with a spatial grid index. Target: smooth interaction (60 fps) with ≥ 2 000 entities per sheet.
- **ARCH-15** `GraphEdit` is not used for the plan; it MAY be reconsidered for board topology editing in a later version.

### 10.4 Tech stack
- **Engine:** Godot **4.7.2 stable** (on the author's Desktop). Version pinned in the repo and in CI.
- **Language:** GDScript only, **static typing everywhere** (typed signatures, typed arrays/dictionaries, `class_name`). Project settings treat untyped declarations and unsafe accesses as **errors**.
- **Tests:** GUT, headless, on Core: commands and inverses, numbering, paste with link preservation, stacks, label solver, unifilaire derivation, rules, SVG golden files.
- **Docs in repo:** this SRD, `ARCHITECTURE.md`, `PACK_FORMAT.md`, `FILE_FORMAT.md`, `KEYMAP.md`.

## 11. Packs and symbol library

### 11.1 Layout (in the repo)
```
packs/
  LICENSE                       # CC0 for everything under packs/
  common/                       # shared by all packs (door, window, stair, grey block art)
  belgium/
    pack.json                   # id, name, version, includes: ["common"]
    symbols.json                # maps SVG files ⇄ core symbol types, properties
    symbols/
      lamp.plan.svg · lamp.unifilaire.svg
      socket.plan.svg · socket.unifilaire.svg
      switch.plan.svg · switch.unifilaire.svg
      switch_two_way.plan.svg · switch_two_way.unifilaire.svg
      panel.plan.svg · meter.plan.svg
    rules.json                  # declarative rules + thresholds (filled by the author from rules.template.json)
    rules.template.json         # template to fill in (provided)
    catalog.json                # breakers, differentials, cables, meters
    cartouche.json              # default cartouche layout and fields
    strings.fr.json             # UI/drawing strings
```
- **PACK-1** A pack is a folder; adding a country = adding a folder; no code change for symbols, thresholds, catalogue, cartouche.
- **PACK-2** `symbols.json` maps each SVG to a **core type** (`lamp`, `switch`, `switch_two_way`, `socket`, `panel`, `meter`, …) and carries properties (default size, `attach: wall|free`, `counts_as_point`, which side faces the wall, label offset). Later versions may add properties without breaking old files (**[TECH]** unknown keys ignored, `format_version` per file).
- **PACK-3** Rules are declarative JSON where possible (thresholds, tables, severity, French message). Complex checks MAY be small GDScript classes registered by id. All rule values are data.
- **PACK-4** Common elements are reused through `includes`; a pack may override any of them.
- **PACK-5** The Belgian symbols are SVG files in the repo, drawn by us.

### 11.2 Symbol SVG authoring convention
- Files are standard SVG (y down, as every SVG tool produces). Core converts on load.
- Origin (0,0) = the symbol's anchor point. For wall-attached symbols the anchor sits on the wall face and the artwork extends **toward the bottom of the page** at rotation 0 (i.e. rotation 0 = "facing down"); rotations are then applied counter-clockwise in Core's math axes.
- `viewBox` centred on the anchor, units = mm at 1:1 world size.
- Stroke-only artwork using `currentColor` (so the app applies colour/theme).
- No CSS, no embedded images, no text elements, no nested transforms.

### 11.3 Supported SVG subset
`g`, `path` (M L H V C S Q A Z, absolute and relative), `line`, `polyline`, `polygon`, `rect`, `circle`, `ellipse`; attributes `fill`, `stroke`, `stroke-width`, `stroke-linecap`, `stroke-linejoin`, `fill-opacity`, `transform` on `g` only (translate/rotate/scale). Anything else is rejected by the validator with a clear message. This subset guarantees that SVG, PDF and screen rendering agree.

### 11.4 Rules template
`packs/belgium/rules.template.json` is provided with every field the v0.1 rules need, all values `null`, each with a French description and a `source` field for the RGIE article reference. The author fills it in and saves it as `rules.json`. The app MUST refuse silently to apply any rule whose value is still `null` and list it in the report as "règle non configurée" (a warning), so that a missing value never produces a false pass.

### 11.5 Initial catalogue (only what the author has used so far)
Added later **on need**. Seed content for `catalog.json`:
- Breakers: C16 A / 3 kA (circuits), C40 A / 3 kA (general).
- Differentials: 40 A / 300 mA / type A / auto-reclosing (head); 40 A / 30 mA / type A (bus).
- Cables: XGB 3G2,5 Cca (circuits); XGB 4x10 (meter to head differential); VOB 3x6 (head to bus).
- Meter: kWh, 27 A.
- Defaults for a new circuit: C16 A / 3 kA, XGB 3G2,5 Cca (flagged as defaulted).

## 12. Look and accessibility (FR-LOOK)

- **FR-LOOK-1** The **default theme reproduces the author's earlier plans** (style tokens below). Goal: same information, same readability, not pixel-exactness.
- **FR-LOOK-2** **Circuit colours on screen** (side panel, selection tint) come from a **colour-blind-safe palette** (e.g. Okabe–Ito for 8 colours, extended with shapes/patterns beyond). Colour is **never the only carrier of information**: the circuit letter is always shown. Exported documents are black-and-white by default.
- **FR-LOOK-3** Fonts: per FR-TXT (Atkinson Hyperlegible default, OpenDyslexic selectable, both OFL; project-wide setting plus per-node override).
- **FR-LOOK-4** UI scaling and a high-contrast option.
- **FR-LOOK-5** French everywhere in v0.1. **[TECH]** all user-facing strings go through `tr()` keys with `fr` as the only shipped locale. Identifiers and code comments are in English.

### 12.1 Default style tokens (measured on the author's earlier A3 plans, 3508 × 2481 px = 8.35 px/mm)
| Token | Value |
|---|---|
| Walls, symbols, frame, text | black `#000000` |
| Wall stroke weight | ≈ 1.4 mm page weight (decided: page weight, not world size) |
| Room labels, free labels | blue `#0D79F2` |
| Étage title | dark red `#900000`, bold, large |
| TGBT / meter markers | green `#1FB672` |
| Doors, windows, grey blocks | light grey `#CACACA` (semi-transparent) |
| Dot grid | light grey dots (≈ `#9A9A9A`) |
| Frame | ≈ 24 mm per column on A3 (17 columns × 8 rows), border at the page edge, cartouche at the bottom |

## 13. Export and persistence

### 13.1 Project file
- **FR-FILE-1** Single file `*.giroflee`, **plain JSON**, UTF-8, pretty-printed with stable key order and entities sorted by id, so it diffs cleanly in git. Contains `format_version`, `pack_ref`, config, cartouche, board, circuits, sheets, entities, acknowledgements and the optional `ui` block.
- **FR-FILE-2** `format_version` plus an explicit **migration** chain; an older file MUST open (never silently drop data).
- **FR-FILE-3** Autosave with silent recovery; no "save changes?" prompt.
- **FR-FILE-4** Background images are stored beside the project (`<name>.giroflee.assets/`), referenced by relative path.

### 13.2 Export (FR-EXP)
- **FR-EXP-1** **SVG is the primary export.** Clean and hand-editable: one `<g>` per layer/role with ids (`walls`, `openings`, `symbols`, `labels`, `frame`, `cartouche`, `provisoire`), symbols as `<symbol>` + `<use>`, real units (mm), a `viewBox` equal to the page, text as live `<text>` with a font stack (**option: convert text to outlines**), so a person can do the last 5% by hand in Inkscape/Affinity.
- **FR-EXP-2** **PDF** is generated from the same DrawList (own minimal vector writer, text outlined; no external converter). Lower priority than SVG; may ship slightly after it within v0.1.
- **FR-EXP-3** **PNG** at configurable DPI (default 300) via SubViewport rendering of the DrawList.
- **FR-EXP-4** Page size and orientation are **export parameters** defaulting to the sheet's own; A-series landscape by default. Uniform scale when retargeted.
- **FR-EXP-5** Export one sheet or all sheets, as a multi-page PDF or a set of files named `<project>-<sheet>.svg|png`.
- **FR-EXP-6** The disclaimer popup of FR-LEG-1 precedes every export.
- **FR-EXP-7** Exports embed no hidden metadata except `generator: Giroflée <version>`.
- **FR-EXP-8** Exports are deterministic: the same project yields byte-identical SVG (needed for golden tests).

## 14. Licensing

- Giroflée code: **GPLv3**.
- **Exported plans carry no condition (commercial use included).** This is compatible with GPLv3: §2 states that output of a covered work is covered only if the output itself constitutes a covered work. The one risk is that exported files **embed our symbol artwork and fonts**. Requirements:
  - **LIC-1** Everything under `packs/` (symbol SVGs, JSON data) is licensed **CC0** (or an equivalent public-domain dedication), with a `LICENSE` file in `packs/`. Only code is GPLv3.
  - **LIC-2** `README` (and the export's `generator` note) state that plans produced with Giroflée are the user's own work with no licence strings attached, **and that the software comes with no liability for the plans produced with it** (consistent with the export disclaimer, FR-LEG-1).
  - **LIC-3** Bundled fonts are SIL OFL (embedding in documents is permitted); licence texts shipped in `third_party/`.
  - **LIC-4** Godot (MIT) and GUT (MIT) are GPLv3-compatible. Third-party licence list in `third_party/NOTICE`.
  - **LIC-5** The Belgian symbols are drawn by us, for practical reasons (clean SVGs, our own conventions). The author's view is that simple technical symbols fall below the originality threshold for copyright; we do not rely on that as a legal claim and do not copy artwork from standards documents.
  - This is an engineering note, not legal advice.

## 15. Validation and acceptance

- **No real or personal plans are used as fixtures** (WA-4). The earlier plans of the author were used once to derive this specification and then removed; they have not been validated by an inspector and are not reference points.
- **15.1 Synthetic fixture.** We author a fictitious house, `fixtures/maison-exemple.giroflee`: 3–4 étages (including a cellar and an attic), about 6 circuits with at least one spare, a triple socket (`count 3`), a switch group with two switches and two lamps, a switch with no lamp (the `?` case), a circuit with more points than the pack's usual limit, a stack, and a head chain with two differentials. Expected unifilaire and SVG outputs are hand-checked once and stored as **golden files** in `tests/golden/`.
- **15.2 Author acceptance.** The author draws their mother's house in Giroflée (spring 2027) in **under 1 hour**, unifilaire generated and validated by Tab+Enter in about a minute, and the result is accepted by a Vinçotte inspector. Baseline: about 5 h in Affinity.

### 15.3 Test strategy (TEST)
- **TEST-1 Unit tests** (GUT, headless) on Core: commands and their inverses, determinism (same commands ⇒ same document), numbering and compaction, Alt-place indices, paste with link preservation, anchoring/stacks (no cycles, detach rules), copy-settings, select-by-filter, label solver, unifilaire derivation, rules and acknowledgement keys, quickbar presets, pack loader and SVG-subset validator, file migrations, SVG exporter (golden files).
- **TEST-2 Scenario tests**: JSON command scripts (`tests/scenarios/*.json`) run through the CLI (ARCH-10), asserting on the resulting document and on derived outputs (unifilaire JSON, report JSON, SVG golden).
- **TEST-3 Replay tests ("automated gameplay", like Factorio)**: a test harness injects **input events** (key presses, mouse moves/clicks/wheel with timestamps) into the real UI scene tree, headless, and asserts on the resulting Document and on the DrawList. Replays are stored in `tests/replays/*.json`, readable and hand-writable. Covered flows include: place walls and openings; `C`+letter then place symbols and check the auto-numbering; Alt-place a lamp with its switches; pipette; quickbar 1–9; copy/paste across étages; duplicate étage; ghost view; circuit focus click/double-click/solo/restore; report Tab/Enter acknowledge; export with and without errors. **[TECH]** GUT's input sender or `Input.parse_input_event`; a small replay player in `tests/support/`. A **replay recorder** (record my session to a replay file) is welcome as a developer tool but is not a v0.1 requirement.
- **TEST-4** Golden files live in `tests/golden/`; a script regenerates them on request, and reviewing the diff is the check. Fixtures are fictitious (section 15.1).
- **TEST-5** CI (section 16) runs everything on every push; a failing test blocks the release job.

## 16. CI/CD and versioning (GitHub Actions) **[TECH]**

Files (provided in this repo): `.github/workflows/ci.yml`, `.github/actions/setup-godot/action.yml`, `VERSION`.

- **CI-1** On every push and pull request: import the project, run the GUT suite headless (includes golden-file tests).
- **CI-2** On every push to `main` that passes the tests, **a new build is released automatically**: Windows export (zip) attached to a GitHub Release.
- **CI-3** **Version scheme `vMAJOR.MINOR.PATCH`:**
  - `MAJOR.MINOR` come from the **`VERSION` file** at the repo root (a single line such as `0.1`). The author changes it by hand and commits it.
  - `PATCH` is **bumped automatically on each build**: next patch = 1 + the highest existing tag `vMAJOR.MINOR.*` (1 if none). Changing `VERSION` therefore restarts the patch counter at 1.
  - While `MAJOR` is 0, releases are marked as **pre-releases**.
  - A commit message containing `[skip release]` skips the release job.
- **CI-4** The version string is written into `project.godot` (`config/version`) before export, so the app and the SVG `generator` metadata show it.
- **CI-5** Godot and export templates are downloaded from the official `godot-builds` release for the pinned version. Linux export can be added later by adding an export preset.
- **CI-6** The repo contains (since M0): `export_presets.cfg` with a preset named **"Windows Desktop"**, a `config/version` key in `project.godot`, GUT in `addons/gut/`, and tests under `tests/`.
- **CI-7** Tests always run through `tools/run-tests.sh`, which fails the run if any test script fails to load. (GUT alone skips such a script silently and still reports success.)
- **CI-8** The Windows export step has not been run yet (export templates for 4.7.2 are not installed on the author's machine); the first CI run on `main` is its first real test.

## 17. Suggested implementation order

Every milestone is done only when its tests (WA-6, section 15.3) pass in CI.

1. **M0** Project scaffold (Godot 4.7.2, strict typing settings, GUT, export preset, CLI entry point, replay harness skeleton, CI green on an empty test).
2. **M1** Core: document model, commands, resolver, history, JSON save/load with migrations, CLI `run-script`, tests.
3. **M2** Canvas: navigation, grid/hints, walls, openings, stairs, grey blocks, text, snapping, selection, copy/paste, tabs/étages, duplicate étage, ghost.
4. **M3** Symbols: pack loader, SVG subset validator, placement, circuits, indices, Alt-place, pipette, quickbar, circuit focus, copy settings, select-by-filter, wall orientation, label solver, anchoring/stacks, `count`.
5. **M4** Unifilaire derivation and rendering; board editor (head chain, bus, circuit order); cartouche editor.
6. **M5** Report panel and rules (template filled by the author).
7. **M6** SVG export (golden tests), disclaimer popup, then PNG, then PDF.
8. **M7** Fonts (Atkinson/OpenDyslexic), colour-blind palette, custom symbols, polish, command palette completeness.

## 18. Decisions log and pending items

**Decided since draft 0.2:** pipette semantics as in FR-SYM-9; stacks = anchoring (FR-STACK); wall line weight = page weight; headless CLI required (ARCH-10); test strategy (15.3); copy settings (FR-EDIT-7); select by filter as commands (FR-EDIT-8); quickbar 1–9 (FR-QB); circuit focus click/solo (FR-FOCUS); no "zoom to content" and no drag-to-repeat or saved-selection library. The exact file schema and the unifilaire pixel layout are **inferred from use** and documented during implementation (`FILE_FORMAT.md`, golden files).

**Pending (per WA-1 nothing below is implemented until the author answers):**
1. **Rule values:** the author fills in `packs/belgium/rules.template.json` later. Until then every rule reports "règle non configurée". Catalogue extras (e.g. the 25 A breaker the author owns) are added on need.
2. **Quickbar:** how a slot is filled (e.g. pick up with the pipette, then assign) and whether the quickbar belongs to the project or to the user.
3. **Keys or gestures** for: anchoring (FR-STACK-2), copy/paste settings (FR-EDIT-7). They exist only as palette commands for now.
