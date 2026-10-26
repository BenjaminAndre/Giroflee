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
var defaults: Dictionary = DEFAULT_DEFAULTS.duplicate()
var snap_enabled: bool = true
var viewport_size: Vector2 = Vector2(1200.0, 800.0)
## Last pointer position (world mm) and its snapped version, for previews and the status bar.
var hover: Vector2 = Vector2.ZERO
var hover_snap: SnapEngine.Result = null
## Where Clipboard text lives. The UI replaces these with the system clipboard.
var clipboard_text: String = ""
var clipboard_get: Callable = Callable()
var clipboard_set: Callable = Callable()

## Bumped whenever the document or the active étage changes; backends use it as a cache key.
var revision: int = 0

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
	return {"overrides": tool.overrides(self)}


func page_list() -> DrawList:
	return PlanRenderer.build(doc(), active_sheet_id, render_options())


func preview_list() -> DrawList:
	return tool.preview(self)


# --- tools --------------------------------------------------------------------------------


func set_tool(name: String) -> void:
	if tool != null:
		tool.cancel(self)
	tool_name = name
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
		_:
			tool_name = "select"
			tool = SelectTool.new()
	changed.emit()


func is_placement_tool() -> bool:
	return tool_name == "door" or tool_name == "window" or tool_name == "stair"


func rotate_placement(ccw: bool) -> void:
	place_rotation = fposmod(place_rotation + (90.0 if ccw else -90.0), 360.0)
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


## Bounding box of the selection in world mm (empty Rect2 when nothing is selected).
func selection_bounds() -> Rect2:
	var rect: Rect2 = Rect2()
	var first: bool = true
	var context: RenderContext = ctx()
	for entity: Entity in selected_entities():
		var b: Rect2 = EntityGeometry.bounds(entity, context)
		rect = b if first else rect.merge(b)
		first = false
	return rect


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
	var items: Array = []
	for entity: Entity in selected_entities():
		var turned: Dictionary = EntityMover.rotated_props_90(entity.type, entity.props, pivot, ccw)
		items.append({"id": entity.id, "props": _changed_props(entity.props, turned)})
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
	var built: Dictionary = Clipboard.to_add_items(parsed, where, session.ids)
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
	for key: String in ["paper_w_mm", "paper_h_mm", "scale_den", "frame_cols", "frame_rows", "grid_step_mm", "hints", "title_pos_mm"]:
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
		var built: Dictionary = Clipboard.to_add_items(parsed, Vector2i(origin_x, origin_y), session.ids)
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


func toggle_ghost() -> void:
	var on: bool = sheet().props["ghost_on"]
	var ghosts: Array = sheet().props["ghost_sheets"]
	var props: Dictionary = {"ghost_on": not on}
	if not on and ghosts.is_empty():
		# first use: show the étage just below in the tab order
		var index: int = doc().sheet_order.find(active_sheet_id)
		if index > 0:
			props["ghost_sheets"] = [doc().sheet_order[index - 1]]
		elif doc().sheet_order.size() > 1:
			props["ghost_sheets"] = [doc().sheet_order[1]]
	set_sheet_props(props)


func toggle_hints() -> void:
	var on: bool = sheet().props["hints"]
	set_sheet_props({"hints": not on})


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
