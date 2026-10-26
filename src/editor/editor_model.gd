class_name EditorModel
extends RefCounted
## Everything the editor window needs, without any widget: the active étage, selection, active
## tool, per-étage views, and all user-level actions. The UI is a thin shell over this class, so
## the whole editor can be driven (and tested) headlessly. Document changes only ever go
## through the Session (SRD ARCH-2).

## Something visible changed (selection, tool, preview, view, document).
signal changed
## The set or order of étages, or the active one, changed (tab bar refresh).
signal sheet_changed
## The UI should open an inline text editor. `entity_id` is "" for a new text.
signal text_requested(world_pos: Vector2, entity_id: String, initial_text: String)
## The UI should let the user rename an étage in place.
signal rename_requested(sheet_id: String)
## Short message for the status bar.
signal notice(message: String)

const DEFAULT_DEFAULTS: Dictionary = {
	"door_width": 900,
	"window_width": 1200,
	"stair_width": 900,
	"stair_steps": 12,
	"stair_tread": 250,
}

var session: Session
var active_sheet_id: String = ""
var selection: Array[String] = []
var tool_name: String = "select"
var tool: Tool = null
## Placement state shared by the door, window and stair tools (H, V, R before clicking).
var place_rotation: float = 0.0
var place_flip_h: bool = false
var place_flip_v: bool = false
## Electric symbols: the circuit new ones join, how many items one symbol stands for (X + digit),
## whether the author rotated the placement by hand (a socket then stops facing away from walls),
## and the circuit and index of the last placement or pipetted symbol (what Alt reuses).
var active_circuit: String = "A"
var place_count: int = 1
var place_rotation_manual: bool = false
var last_placed: Dictionary = {}
## First key of a two-key command waiting for its second ("C" circuit, "X" count), "" when none.
var pending_prefix: String = ""
## Which circuits are greyed out in this window (view state, never saved).
var focus: CircuitFocus = CircuitFocus.new()
var quickbar: Quickbar = Quickbar.new()
## Style properties copied with "Copier les propriétés" ({} when nothing was copied).
var settings_clipboard: Dictionary = {}
var defaults: Dictionary = DEFAULT_DEFAULTS.duplicate()
var snap_enabled: bool = true
var viewport_size: Vector2 = Vector2(1200.0, 800.0)
## Last pointer position (world mm) and its snapped version, for previews and the status bar.
var hover: Vector2 = Vector2.ZERO
var hover_snap: SnapEngine.Result = null
## Transform handle under the pointer ("nw", "rotate", "vertex"...), "" if none; drives the cursor.
var hover_handle: String = ""
## Where Clipboard text lives. The UI replaces these with the system clipboard.
var clipboard_text: String = ""
var clipboard_get: Callable = Callable()
var clipboard_set: Callable = Callable()

## Bumped whenever the document or the active étage changes; backends use it as a cache key.
var revision: int = 0
## Bumped when only the look changes (circuit focus), so that drawing caches refresh without the
## project counting as modified.
var view_revision: int = 0

var _views: Dictionary = {}
var _order_seen: Array[String] = []


func _init(p_session: Session) -> void:
	session = p_session
	session.changed.connect(_on_session_changed)
	_ensure_a_sheet()
	_order_seen = doc().sheet_order.duplicate()
	if doc().sheet_order.size() > 0:
		active_sheet_id = doc().sheet_order[0]
	set_tool("select")


# --- accessors ----------------------------------------------------------------------------


func doc() -> Document:
	return session.document()


func sheet() -> Sheet:
	return doc().get_sheet(active_sheet_id)


func ctx() -> RenderContext:
	return RenderContext.for_sheet(doc(), sheet())


func new_id() -> String:
	return session.ids.next_uuid()


func view() -> ViewTransform:
	if not _views.has(active_sheet_id):
		var fresh: ViewTransform = ViewTransform.new()
		fresh.viewport = viewport_size
		fresh.fit_rect(FrameBuilder.page_rect(sheet()))
		_views[active_sheet_id] = fresh
	var current: ViewTransform = _views[active_sheet_id]
	return current


func set_viewport_size(size: Vector2) -> void:
	viewport_size = size
	for key: Variant in _views.keys():
		var v: ViewTransform = _views[key]
		v.viewport = size
		if not v.user_adjusted and size.x > 50.0 and size.y > 50.0:
			var view_sheet: Sheet = doc().get_sheet(str(key))
			if view_sheet != null:
				v.fit_rect(FrameBuilder.page_rect(view_sheet))
	changed.emit()


## Pick radius in world mm for `pixels` on screen at the current zoom.
func tolerance(pixels: float = 10.0) -> float:
	return pixels / view().zoom


## Spatial index of the active étage (rebuilt only after a document change).
func spatial() -> SpatialIndex:
	return SpatialIndex.for_sheet(doc(), sheet(), ctx())


func snap(world: Vector2, exclude: Array = [], options: Dictionary = {}) -> SnapEngine.Result:
	var merged: Dictionary = options.duplicate()
	merged["exclude"] = exclude
	merged["index"] = spatial()
	if not snap_enabled:
		merged["grid"] = false
		merged["objects"] = false
	return SnapEngine.snap(sheet(), world, tolerance(), merged)


func render_options() -> Dictionary:
	return {"overrides": tool.overrides(self), "circuit_colors": true, "dimmed": focus.dimmed_letters()}


func page_list() -> DrawList:
	return PlanRenderer.build(doc(), active_sheet_id, render_options())


func preview_list() -> DrawList:
	return tool.preview(self)


# --- tools --------------------------------------------------------------------------------


func set_tool(name: String) -> void:
	if tool != null:
		tool.cancel(self)
	tool_name = name
	hover_handle = ""
	match name:
		"wall":
			tool = WallTool.new()
		"door":
			tool = OpeningTool.new("door")
		"window":
			tool = OpeningTool.new("window")
		"stair":
			tool = StairTool.new()
		"block":
			tool = BlockTool.new()
		"text":
			tool = TextTool.new()
		"anchor":
			tool = AnchorTool.new()
		_:
			if SymbolLibrary.for_pack(doc().pack_ref).has_type(name):
				tool = SymbolTool.new(name)
			else:
				tool_name = "select"
				tool = SelectTool.new()
	changed.emit()


func is_placement_tool() -> bool:
	return tool_name == "door" or tool_name == "window" or tool_name == "stair" or tool is SymbolTool


func rotate_placement(ccw: bool) -> void:
	place_rotation = fposmod(place_rotation + (90.0 if ccw else -90.0), 360.0)
	place_rotation_manual = true
	changed.emit()


func flip_placement(horizontal: bool) -> void:
	if horizontal:
		place_flip_h = not place_flip_h
	else:
		place_flip_v = not place_flip_v
	changed.emit()


# --- selection ----------------------------------------------------------------------------


func set_selection(ids: Array) -> void:
	var cleaned: Array[String] = []
	for raw_id: Variant in ids:
		var entity_id: String = str(raw_id)
		if sheet().entities.has(entity_id) and not cleaned.has(entity_id):
			cleaned.append(entity_id)
	selection = cleaned
	changed.emit()


func clear_selection() -> void:
	set_selection([])


func toggle_selected(entity_id: String) -> void:
	var next: Array = selection.duplicate()
	if next.has(entity_id):
		next.erase(entity_id)
	else:
		next.append(entity_id)
	set_selection(next)


func select_all() -> void:
	set_selection(sheet().sorted_entity_ids())


func selected_entities() -> Array[Entity]:
	var out: Array[Entity] = []
	for entity_id: String in selection:
		if sheet().entities.has(entity_id):
			var entity: Entity = sheet().entities[entity_id]
			out.append(entity)
	return out


## Bounding box of the selection in world mm (empty Rect2 when nothing is selected). With
## `core`, line thickness is ignored (what the transform box scales and rotates).
func selection_bounds(core: bool = false) -> Rect2:
	var rect: Rect2 = Rect2()
	var first: bool = true
	var context: RenderContext = ctx()
	for entity: Entity in selected_entities():
		var b: Rect2 = EntityGeometry.core_bounds(entity, context) if core else EntityGeometry.bounds(entity, context)
		rect = b if first else rect.merge(b)
		first = false
	return rect


# --- circuits and electric symbols ----------------------------------------------------------


## Click on a circuit in the side panel: greys it out or shows it again.
func focus_toggle(letter: String) -> void:
	focus.toggle(letter)
	view_revision += 1
	changed.emit()


## Double-click on a circuit: shows only that one, or restores what was visible before.
func focus_solo(letter: String, all_letters: Array[String]) -> void:
	focus.solo(letter, all_letters)
	view_revision += 1
	changed.emit()


## Ids on this étage that circuit focus keeps out of picking and box selection (FR-FOCUS-1).
func focus_excluded() -> Array:
	var out: Array = []
	if focus.dimmed_letters().is_empty():
		return out
	for entity_id: String in sheet().sorted_entity_ids():
		var entity: Entity = sheet().entities[entity_id]
		if entity.type == "symbol" and focus.is_dimmed(str(entity.props["circuit"])):
			out.append(entity_id)
	return out


## Index a new symbol of the active circuit gets: the last placed one's with Alt (same point),
## otherwise the next free one.
func index_for_placement(reuse: bool) -> int:
	if reuse and not last_placed.is_empty() and last_placed["circuit"] == active_circuit:
		var index: int = last_placed["index"]
		return index
	return Numbering.next_index(doc(), active_circuit)


## Remembers a placement so that Alt can link the next symbol to it.
func note_placed(props: Dictionary) -> void:
	var circuit: String = props.get("circuit", "")
	var index: int = props.get("index", 0)
	if not circuit.is_empty() and index > 0:
		last_placed = {"circuit": circuit, "index": index}


func set_active_circuit(letter: String) -> void:
	if not CircuitPalette.is_letter(letter):
		return
	active_circuit = letter
	changed.emit()


## C + letter: moves the selected symbols to that circuit (next free indices, links kept); with
## nothing selected it only changes the circuit new symbols join (FR-SYM-7).
func assign_circuit(letter: String) -> void:
	if not CircuitPalette.is_letter(letter):
		return
	if selection.is_empty():
		set_active_circuit(letter)
		return
	var items: Array = Numbering.reassign_items(doc(), active_sheet_id, selection, letter)
	if items.is_empty():
		notice.emit(tr("Aucun symbole à réassigner dans la sélection"))
		return
	update_entities(items)


## X + digit: the count of the selected symbols; with nothing selected, of the next placements.
func set_count(count: int) -> void:
	if count < 1:
		return
	var items: Array = []
	for entity: Entity in selected_entities():
		if entity.type == "symbol":
			items.append({"id": entity.id, "props": {"count": count}})
	if items.is_empty():
		place_count = count
		changed.emit()
		return
	update_entities(items)


## A: switch to the tool of the entity under the cursor, carrying its settings (FR-SYM-9). Symbols of
## a greyed-out circuit are not picked. Returns the picked id ("" when nothing).
func pipette() -> String:
	var picked: String = HitTest.pick(sheet(), ctx(), hover, tolerance(), focus_excluded(), spatial())
	if picked.is_empty():
		notice.emit(tr("Rien à copier sous le curseur"))
		return ""
	var entity: Entity = sheet().entities[picked]
	var props: Dictionary = entity.props
	match entity.type:
		"symbol":
			set_tool(str(props["symbol_type"]))
			place_rotation = props["rotation"]
			place_flip_h = props["flip_h"]
			place_flip_v = props["flip_v"]
			place_count = props["count"]
			place_rotation_manual = true
			var circuit: String = props["circuit"]
			if not circuit.is_empty():
				active_circuit = circuit
				note_placed(props)
		"opening":
			var kind: String = props["kind"]
			defaults["%s_width" % kind] = props["width_mm"]
			set_tool(kind)
			place_rotation = props["rotation"]
			place_flip_h = props["flip_h"]
			place_flip_v = props["flip_v"]
		"stair":
			defaults["stair_width"] = props["width_mm"]
			defaults["stair_steps"] = props["steps"]
			defaults["stair_tread"] = props["tread_mm"]
			set_tool("stair")
			place_rotation = props["rotation"]
			place_flip_h = props["flip_h"]
			place_flip_v = props["flip_v"]
		"wall":
			set_config("wall_weight_mm", props["weight_mm"])
			set_tool("wall")
		"grey_block":
			set_tool("block")
		"text":
			set_tool("text")
	changed.emit()
	return picked


## Re-solves label and badge positions: of the selected symbols, or of every unpinned symbol of the
## étage when nothing is selected ("Replacer les étiquettes").
func relabel() -> void:
	var only: Array = []
	for entity: Entity in selected_entities():
		if entity.type == "symbol":
			only.append(entity.id)
	var solved: Dictionary = LabelSolver.solve(sheet(), ctx(), only)
	var items: Array = []
	for key: Variant in solved.keys():
		var entity_id: String = str(key)
		var entry: Dictionary = solved[key]
		var current: Entity = sheet().entities[entity_id]
		var before: Dictionary = current.props
		var diff: Dictionary = _changed_props(before, entry)
		if not diff.is_empty():
			items.append({"id": entity_id, "props": diff})
	if items.is_empty():
		notice.emit(tr("Étiquettes déjà bien placées"))
		return
	update_entities(items)


## "Compacter la numérotation": closes the gaps in the indices of one circuit, or of all ("").
func compact_numbering(circuit: String = "") -> void:
	var plan: Dictionary = Numbering.compact_plan(doc(), circuit)
	if plan.is_empty():
		notice.emit(tr("Numérotation déjà compacte"))
		return
	var commands: Array[Command] = []
	for key: Variant in plan.keys():
		commands.append(session.command("entity.update", {"sheet": str(key), "items": plan[key]}))
	var result: CommandResult = session.run(commands)
	if not result.ok:
		notice.emit(result.error)


## "Ancrer à un symbole": waits for a click on the parent, the selected symbols being the children.
func begin_anchor() -> void:
	for entity: Entity in selected_entities():
		if entity.type == "symbol":
			set_tool("anchor")
			return
	notice.emit(tr("Sélectionnez d'abord les symboles à ancrer"))


## Anchors the selected symbols to `parent_id`, keeping every symbol where it is (FR-STACK-1).
func anchor_selection_to(parent_id: String) -> CommandResult:
	var parent: Entity = sheet().entities[parent_id]
	var parent_pos: Vector2 = EntityGeometry.vec(parent.props["pos"])
	var items: Array = []
	for entity: Entity in selected_entities():
		if entity.type != "symbol" or entity.id == parent_id:
			continue
		var offset: Vector2 = EntityGeometry.vec(entity.props["pos"]) - parent_pos
		items.append({"id": entity.id, "props": {"anchor_parent": parent_id, "anchor_offset": [roundi(offset.x), roundi(offset.y)]}})
	return update_entities(items)


## "Détacher": the selected symbols stay in place and stop following a parent.
func detach_selection() -> void:
	var items: Array = []
	for entity: Entity in selected_entities():
		var parent: String = entity.props["anchor_parent"] if entity.type == "symbol" else ""
		if not parent.is_empty():
			items.append({"id": entity.id, "props": {"anchor_parent": "", "anchor_offset": [0, 0]}})
	if items.is_empty():
		notice.emit(tr("Aucun symbole ancré dans la sélection"))
		return
	update_entities(items)


## "Copier les propriétés": remembers the style of the one selected entity (FR-EDIT-7).
func copy_settings() -> void:
	var chosen: Array[Entity] = selected_entities()
	if chosen.size() != 1:
		notice.emit(tr("Sélectionnez un seul élément dont copier les propriétés"))
		return
	settings_clipboard = StyleProps.capture(chosen[0])
	if settings_clipboard.is_empty():
		notice.emit(tr("Cet élément n'a pas de propriétés à copier"))
		return
	notice.emit(tr("Propriétés copiées"))


## "Coller les propriétés": applies them to the selected entities of the same type.
func paste_settings() -> void:
	if settings_clipboard.is_empty():
		notice.emit(tr("Aucune propriété copiée"))
		return
	var items: Array = StyleProps.items(sheet(), selection, settings_clipboard)
	if items.is_empty():
		notice.emit(tr("Rien à modifier dans la sélection"))
		return
	update_entities(items)


## "Libérer les étiquettes": the selected symbols (all when nothing is selected) are no longer pinned,
## so that "Replacer les étiquettes" may move their labels again.
func unpin_labels() -> void:
	var items: Array = []
	var chosen: Array[Entity] = selected_entities()
	if chosen.is_empty():
		for entity_id: String in sheet().sorted_entity_ids():
			chosen.append(sheet().entities[entity_id])
	for entity: Entity in chosen:
		if entity.type == "symbol" and entity.props["label_pinned"]:
			items.append({"id": entity.id, "props": {"label_pinned": false}})
	if items.is_empty():
		notice.emit(tr("Aucune étiquette fixée à libérer"))
		return
	update_entities(items)


## Keeps the current tool and its settings in quickbar slot 1-9.
func store_quickbar(slot: int) -> void:
	var preset: Dictionary = Quickbar.capture(self)
	if preset.is_empty():
		notice.emit(tr("Choisissez d'abord un outil à mémoriser"))
		return
	quickbar.assign(slot, preset)
	changed.emit()
	notice.emit(tr("Case %d mémorisée") % slot)


## Digit key: switches to the preset of the slot.
func use_quickbar(slot: int) -> void:
	if not quickbar.is_filled(slot):
		notice.emit(tr("Case %d vide : mémorisez un outil depuis la palette de commandes") % slot)
		return
	Quickbar.apply(self, quickbar.preset(slot))


## Selects `ids` (the select-by-filter commands), skipping symbols of greyed-out circuits.
func select_filtered(ids: Array, what: String) -> void:
	var skip: Array = focus_excluded()
	var kept: Array = []
	for raw_id: Variant in ids:
		if not skip.has(raw_id):
			kept.append(raw_id)
	set_tool("select")
	set_selection(kept)
	notice.emit(tr("%d sélectionné(s) : %s") % [kept.size(), what])


# --- entity actions -----------------------------------------------------------------------


## Adds entities ([{id, type, props}]) in one undo step. Returns the result.
func add_entities(items: Array) -> CommandResult:
	return _run("entity.add", {"sheet": active_sheet_id, "items": items})


func add_text(world_pos: Vector2, text: String, role: String = "free") -> CommandResult:
	var id: String = new_id()
	var props: Dictionary = {"pos": [roundi(world_pos.x), roundi(world_pos.y)], "text": text, "role": role}
	var result: CommandResult = add_entities([{"id": id, "type": "text", "props": props}])
	if result.ok:
		set_selection([id])
	return result


## Replaces the text of an existing label. An empty text deletes it.
func set_text(entity_id: String, text: String) -> CommandResult:
	if text.is_empty():
		return _run("entity.remove", {"sheet": active_sheet_id, "ids": [entity_id]})
	return update_entities([{"id": entity_id, "props": {"text": text}}])


func update_entities(items: Array) -> CommandResult:
	return _run("entity.update", {"sheet": active_sheet_id, "items": items})


## Applies the same partial props to several entities (Properties panel multi-edit).
func apply_props(ids: Array, props: Dictionary) -> CommandResult:
	var items: Array = []
	for raw_id: Variant in ids:
		items.append({"id": str(raw_id), "props": props.duplicate(true)})
	return update_entities(items)


func move_entities(ids: Array, delta: Vector2i) -> CommandResult:
	return _run("entity.move", {"sheet": active_sheet_id, "ids": ids, "delta": [delta.x, delta.y]})


func delete_selection() -> void:
	if selection.is_empty():
		return
	var ids: Array = selection.duplicate()
	var result: CommandResult = _run("entity.remove", {"sheet": active_sheet_id, "ids": ids})
	if result.ok:
		clear_selection()


## Moves the selection by whole grid steps (arrow keys).
func nudge(steps_x: int, steps_y: int) -> void:
	if selection.is_empty():
		return
	var step: int = sheet().props["grid_step_mm"]
	move_entities(selection.duplicate(), Vector2i(steps_x * step, steps_y * step))


func flip_selection(horizontal: bool) -> void:
	var key: String = "flip_h" if horizontal else "flip_v"
	var items: Array = []
	for entity: Entity in selected_entities():
		if EntityMover.can_flip(entity.type):
			var flipped: Dictionary = EntityMover.flipped_props(entity.props, horizontal)
			items.append({"id": entity.id, "props": {key: flipped[key]}})
	if not items.is_empty():
		update_entities(items)


## Rotates the selection by 90 degrees about the centre of its bounds.
func rotate_selection(ccw: bool) -> void:
	if selection.is_empty():
		return
	var c: Vector2 = selection_bounds().get_center()
	var pivot: Vector2i = Vector2i(roundi(c.x), roundi(c.y))
	var carried: Dictionary = SelectionTransform.with_followers(sheet(), selection)
	var turned_by_id: Dictionary = {}
	var carried_ids: Array = carried["ids"]
	for raw_id: Variant in carried_ids:
		var entity: Entity = sheet().entities[str(raw_id)]
		turned_by_id[entity.id] = EntityMover.rotated_props_90(entity.type, entity.props, pivot, ccw)
	apply_transform(turned_by_id)


## Commits the result of a transform-box gesture ({id: new props}) as one undo step.
func apply_transform(raw_props_by_id: Dictionary) -> void:
	var props_by_id: Dictionary = AnchorRules.recompute_offsets(sheet(), raw_props_by_id)
	var items: Array = []
	for key: Variant in props_by_id.keys():
		var entity_id: String = str(key)
		var entity: Entity = sheet().entities[entity_id]
		var after: Dictionary = props_by_id[key]
		var diff: Dictionary = _changed_props(entity.props, after)
		if not diff.is_empty():
			items.append({"id": entity_id, "props": diff})
	if not items.is_empty():
		update_entities(items)


## Subset of `after` whose values differ from `before`.
static func _changed_props(before: Dictionary, after: Dictionary) -> Dictionary:
	var diff: Dictionary = {}
	for key: Variant in after.keys():
		if not before.has(key) or before[key] != after[key]:
			diff[key] = after[key]
	return diff


# --- clipboard ----------------------------------------------------------------------------


func copy_selection() -> void:
	var text: String = Clipboard.serialize(sheet(), selection)
	if text.is_empty():
		notice.emit(tr("Rien à copier"))
		return
	_set_clipboard(text)
	notice.emit(tr("Sélection copiée"))


func cut_selection() -> void:
	copy_selection()
	delete_selection()


## Pastes at `target` (world mm, snapped to the grid) or, without one, slightly offset.
func paste(target: Variant = null) -> void:
	var parsed: Dictionary = Clipboard.parse(_get_clipboard())
	if not JsonUtil.flag(parsed, "ok"):
		notice.emit(tr("Rien à coller"))
		return
	var origin: Array = parsed["origin"]
	var where: Vector2i
	if target is Vector2:
		var t: Vector2 = target
		var snapped: Vector2 = snap(t).pos
		where = Vector2i(roundi(snapped.x), roundi(snapped.y))
	else:
		var step: int = sheet().props["grid_step_mm"]
		var ox: int = origin[0]
		var oy: int = origin[1]
		where = Vector2i(ox + 2 * step, oy - 2 * step)
	var built: Dictionary = Clipboard.to_add_items(parsed, where, session.ids, doc())
	var items: Array = built["items"]
	var new_ids: Array = built["new_ids"]
	var result: CommandResult = add_entities(items)
	if result.ok:
		set_selection(new_ids)


func duplicate_selection() -> void:
	if selection.is_empty():
		return
	var saved: String = _get_clipboard()
	copy_selection()
	paste()
	_set_clipboard(saved)


func _get_clipboard() -> String:
	if clipboard_get.is_valid():
		var text: String = clipboard_get.call()
		return text
	return clipboard_text


func _set_clipboard(text: String) -> void:
	clipboard_text = text
	if clipboard_set.is_valid():
		clipboard_set.call(text)


# --- text editing -------------------------------------------------------------------------


## F2: edit the single selected text in place, or rename the étage when nothing is selected.
func edit_selection_text() -> void:
	var entities: Array[Entity] = selected_entities()
	if entities.size() == 1 and entities[0].type == "text":
		var text: String = entities[0].props["text"]
		text_requested.emit(EntityGeometry.vec(entities[0].props["pos"]), entities[0].id, text)
	elif selection.is_empty():
		rename_requested.emit(active_sheet_id)


# --- étages -------------------------------------------------------------------------------


func set_active_sheet(sheet_id: String) -> void:
	if not doc().sheets.has(sheet_id) or sheet_id == active_sheet_id:
		return
	if tool != null:
		tool.cancel(self)
	active_sheet_id = sheet_id
	selection = []
	revision += 1
	sheet_changed.emit()
	changed.emit()


func cycle_sheet(step: int) -> void:
	var order: Array[String] = doc().sheet_order
	if order.size() < 2:
		return
	var index: int = order.find(active_sheet_id)
	set_active_sheet(order[posmod(index + step, order.size())])


## New étage after the active one; it inherits paper, scale, grid and frame settings.
func new_sheet() -> void:
	var source: Sheet = sheet()
	var props: Dictionary = {"name": _free_name(tr("Étage"))}
	for key: String in ["paper_w_mm", "paper_h_mm", "scale_den", "grid_step_mm"]:
		props[key] = JsonUtil.deep_copy(source.props[key])
	var sheet_id: String = new_id()
	var index: int = doc().sheet_order.find(active_sheet_id) + 1
	var result: CommandResult = _run("sheet.add", {"id": sheet_id, "kind": "plan", "props": props, "index": index})
	if result.ok:
		set_active_sheet(sheet_id)


## Copies the active étage after itself: the architecture only, or everything with `with_symbols`
## (SRD FR-EDIT-4). Texts (room names) are architecture.
func duplicate_sheet(with_symbols: bool) -> void:
	var source: Sheet = sheet()
	var props: Dictionary = source.props.duplicate(true)
	props["name"] = _free_name("%s (%s)" % [source.display_name(), tr("copie")])
	var new_sheet_id: String = new_id()
	var index: int = doc().sheet_order.find(active_sheet_id) + 1
	var commands: Array[Command] = [session.command("sheet.add", {"id": new_sheet_id, "kind": "plan", "props": props, "index": index})]
	var text: String = Clipboard.serialize(source, source.sorted_entity_ids(), with_symbols)
	if not text.is_empty():
		var parsed: Dictionary = Clipboard.parse(text)
		var origin: Array = parsed["origin"]
		var origin_x: int = origin[0]
		var origin_y: int = origin[1]
		var built: Dictionary = Clipboard.to_add_items(parsed, Vector2i(origin_x, origin_y), session.ids, doc())
		commands.append(session.command("entity.add", {"sheet": new_sheet_id, "items": built["items"]}))
	var result: CommandResult = session.run(commands)
	if result.ok:
		set_active_sheet(new_sheet_id)
	else:
		notice.emit(result.error)


func delete_sheet() -> void:
	if doc().sheet_order.size() <= 1:
		notice.emit(tr("Impossible de supprimer le dernier étage"))
		return
	var order: Array[String] = doc().sheet_order.duplicate()
	var index: int = order.find(active_sheet_id)
	var doomed: String = active_sheet_id
	var result: CommandResult = _run("sheet.remove", {"id": doomed})
	if result.ok:
		var remaining: Array[String] = doc().sheet_order
		set_active_sheet(remaining[mini(index, remaining.size() - 1)])


func rename_sheet(sheet_id: String, name: String) -> void:
	var trimmed: String = name.strip_edges()
	if trimmed.is_empty():
		return
	_run("sheet.update", {"id": sheet_id, "props": {"name": trimmed}})


func set_sheet_props(props: Dictionary) -> CommandResult:
	return _run("sheet.update", {"id": active_sheet_id, "props": props})


func set_config(key: String, value: Variant) -> CommandResult:
	return _run("doc.set", {"section": "config", "key": key, "value": value})


## The ghost-view switch is project-wide; which étages are ghosted stays per sheet. On first use
## in an étage with no choice yet, the étage just below in the tab order is shown. One undo step.
func toggle_ghost() -> void:
	var on: bool = doc().config["ghost_on"]
	var commands: Array[Command] = [session.command("doc.set", {"section": "config", "key": "ghost_on", "value": not on})]
	var ghosts: Array = sheet().props["ghost_sheets"]
	if not on and ghosts.is_empty():
		var index: int = doc().sheet_order.find(active_sheet_id)
		var pick: String = ""
		if index > 0:
			pick = doc().sheet_order[index - 1]
		elif doc().sheet_order.size() > 1:
			pick = doc().sheet_order[1]
		if not pick.is_empty():
			commands.append(session.command("sheet.update", {"id": active_sheet_id, "props": {"ghost_sheets": [pick]}}))
	var result: CommandResult = session.run(commands)
	if not result.ok:
		notice.emit(result.error)


func toggle_hints() -> void:
	var on: bool = doc().config["hints"]
	set_config("hints", not on)


# --- history ------------------------------------------------------------------------------


func undo() -> void:
	if tool != null and tool.is_active():
		tool.cancel(self)
		return
	if not session.undo() and not session.last_error.is_empty():
		notice.emit(session.last_error)


func redo() -> void:
	if not session.redo() and not session.last_error.is_empty():
		notice.emit(session.last_error)


# --- internals ----------------------------------------------------------------------------


func _run(type: String, payload: Dictionary) -> CommandResult:
	var result: CommandResult = session.run_one(type, payload)
	if not result.ok:
		notice.emit(result.error)
	return result


func _ensure_a_sheet() -> void:
	if doc().sheet_order.is_empty():
		session.run_one("sheet.add", {"id": new_id(), "kind": "plan", "props": {"name": tr("Rez")}})
		session.history.clear()


func _free_name(base: String) -> String:
	var taken: Array[String] = []
	for sheet_id: String in doc().sheet_order:
		taken.append(doc().get_sheet(sheet_id).display_name())
	if not taken.has(base):
		return base
	var n: int = 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func _on_session_changed() -> void:
	var order: Array[String] = doc().sheet_order
	if not order.has(active_sheet_id):
		var old_index: int = _order_seen.find(active_sheet_id)
		active_sheet_id = order[clampi(old_index, 0, order.size() - 1)] if not order.is_empty() else ""
		selection = []
	else:
		var kept: Array[String] = []
		for entity_id: String in selection:
			if sheet().entities.has(entity_id):
				kept.append(entity_id)
		selection = kept
	_order_seen = order.duplicate()
	revision += 1
	sheet_changed.emit()
	changed.emit()
