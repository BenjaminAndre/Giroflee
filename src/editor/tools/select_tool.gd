class_name SelectTool
extends Tool
## The default tool: click and Shift-click to select, drag on empty space for a box selection,
## drag a selected entity to move the selection (with snapping), drag a handle to reshape a
## wall vertex or resize a grey block (SRD FR-EDIT-1). Each gesture is one undo step.

enum Mode { IDLE, BOX, MOVE, HANDLE }

var _mode: Mode = Mode.IDLE
var _target_id: String = ""
var _press_snap: Vector2 = Vector2.ZERO
var _delta: Vector2i = Vector2i.ZERO
var _collapse_on_release: bool = false
var _box: Rect2 = Rect2()
var _box_start: Vector2 = Vector2.ZERO
var _handle: Dictionary = {}
var _handle_props: Dictionary = {}


func tool_name() -> String:
	return "select"


func is_active() -> bool:
	return _mode != Mode.IDLE


## Handles shown for a single selected wall (its vertices) or grey block (its corners).
## Each is {"pos": Vector2, "kind": "vertex"|"corner", "index": int, "entity": id}.
static func handles_for(model: EditorModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if model.selection.size() != 1:
		return out
	var entity: Entity = model.selected_entities()[0]
	if entity.type == "wall":
		var points: Array = entity.props["points"]
		for i: int in points.size():
			out.append({"pos": EntityGeometry.vec(points[i]), "kind": "vertex", "index": i, "entity": entity.id})
	elif entity.type == "grey_block":
		var rotation: float = entity.props["rotation"]
		if rotation == 0.0:
			var corners: PackedVector2Array = EntityGeometry.block_polygon(entity.props)
			for i: int in corners.size():
				out.append({"pos": corners[i], "kind": "corner", "index": i, "entity": entity.id})
	return out


func press(model: EditorModel, input: ToolInput) -> void:
	var handle: Dictionary = _handle_at(model, input.world, input.tolerance * 1.4)
	if not handle.is_empty():
		_mode = Mode.HANDLE
		_handle = handle
		_target_id = str(handle["entity"])
		_handle_props = {}
		model.changed.emit()
		return
	var picked: String = HitTest.pick(model.sheet(), model.ctx(), input.world, input.tolerance, [], model.spatial())
	if not picked.is_empty():
		if input.double_click:
			var entity: Entity = model.sheet().entities[picked]
			if entity.type == "text":
				model.set_selection([picked])
				model.edit_selection_text()
				return
		if input.shift:
			model.toggle_selected(picked)
			return
		_collapse_on_release = model.selection.has(picked) and model.selection.size() > 1
		if not model.selection.has(picked):
			model.set_selection([picked])
		_mode = Mode.MOVE
		_target_id = picked
		_delta = Vector2i.ZERO
		_press_snap = model.snap(input.world, model.selection).pos
		return
	if not input.shift:
		model.clear_selection()
	_mode = Mode.BOX
	_box_start = input.world
	_box = Rect2(input.world, Vector2.ZERO)
	model.changed.emit()


func move(model: EditorModel, input: ToolInput) -> void:
	match _mode:
		Mode.BOX:
			_box = Rect2(_box_start, input.world - _box_start).abs()
		Mode.MOVE:
			var current: Vector2 = model.snap(input.world, model.selection).pos
			var d: Vector2 = current - _press_snap
			_delta = Vector2i(roundi(d.x), roundi(d.y))
		Mode.HANDLE:
			var at: Vector2 = model.snap(input.world, [_target_id]).pos
			_handle_props = _props_with_handle(model, at)
	model.changed.emit()


func release(model: EditorModel, input: ToolInput) -> void:
	var finished: Mode = _mode
	_mode = Mode.IDLE
	match finished:
		Mode.BOX:
			var rect: Rect2 = Rect2(_box_start, input.world - _box_start).abs()
			if rect.size.length() > input.tolerance:
				var hits: Array[String] = HitTest.in_rect(model.sheet(), model.ctx(), rect, [], model.spatial())
				if input.shift:
					var merged: Array = model.selection.duplicate()
					for entity_id: String in hits:
						if not merged.has(entity_id):
							merged.append(entity_id)
					model.set_selection(merged)
				else:
					model.set_selection(hits)
		Mode.MOVE:
			if _delta != Vector2i.ZERO:
				model.move_entities(model.selection.duplicate(), _delta)
			elif _collapse_on_release and not input.shift:
				model.set_selection([_target_id])
		Mode.HANDLE:
			if not _handle_props.is_empty():
				var entity: Entity = model.sheet().entities[_target_id]
				var diff: Dictionary = EditorModel._changed_props(entity.props, _handle_props)
				if not diff.is_empty():
					model.update_entities([{"id": _target_id, "props": diff}])
	_delta = Vector2i.ZERO
	_handle = {}
	_handle_props = {}
	_collapse_on_release = false
	model.changed.emit()


func cancel(model: EditorModel) -> bool:
	if _mode == Mode.IDLE:
		return false
	_mode = Mode.IDLE
	_delta = Vector2i.ZERO
	_handle = {}
	_handle_props = {}
	model.changed.emit()
	return true


func overrides(model: EditorModel) -> Dictionary:
	var out: Dictionary = {}
	if _mode == Mode.MOVE and _delta != Vector2i.ZERO:
		var moving: Array = model.selection.duplicate()
		for entity_id: String in model.sheet().sorted_entity_ids():
			var entity: Entity = model.sheet().entities[entity_id]
			var carried: bool = moving.has(entity_id)
			if entity.type == "opening":
				var host: String = entity.props["host_wall"]
				carried = carried or (not host.is_empty() and moving.has(host))
			if carried:
				out[entity_id] = EntityMover.shifted_props(entity.type, entity.props, _delta.x, _delta.y)
	elif _mode == Mode.HANDLE and not _handle_props.is_empty():
		out[_target_id] = _handle_props
	return out


func has_overlay_rect() -> bool:
	return _mode == Mode.BOX


func overlay_rect() -> Rect2:
	return _box


func hint(_model: EditorModel) -> String:
	return "Sélection : clic / Maj+clic, glisser pour encadrer ou déplacer · Suppr = supprimer · R, H, V = tourner / retourner"


func _handle_at(model: EditorModel, world: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = radius
	for handle: Dictionary in SelectTool.handles_for(model):
		var pos: Vector2 = handle["pos"]
		var distance: float = world.distance_to(pos)
		if distance <= best_distance:
			best_distance = distance
			best = handle
	return best


## Props of the dragged entity with the grabbed handle moved to `at`.
func _props_with_handle(model: EditorModel, at: Vector2) -> Dictionary:
	var entity: Entity = model.sheet().entities[_target_id]
	var props: Dictionary = entity.props.duplicate(true)
	var index: int = _handle["index"]
	var target: Array = [roundi(at.x), roundi(at.y)]
	if entity.type == "wall":
		var points: Array = props["points"]
		points[index] = target
		var last: int = points.size() - 1
		var first_point: Array = entity.props["points"][0]
		var last_point: Array = entity.props["points"][last]
		if last > 2 and first_point == last_point and (index == 0 or index == last):
			points[0] = target
			points[last] = target
		props["points"] = points
		return props
	# grey block: the opposite corner stays, the dragged one follows the cursor
	var corners: PackedVector2Array = EntityGeometry.block_polygon(entity.props)
	var opposite: Vector2 = corners[(index + 2) % 4]
	var rect: Rect2 = Rect2(opposite, at - opposite).abs()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return entity.props.duplicate(true)
	props["pos"] = [roundi(rect.position.x), roundi(rect.position.y)]
	props["size"] = [roundi(rect.size.x), roundi(rect.size.y)]
	return props
