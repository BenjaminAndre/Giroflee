class_name SelectTool
extends Tool
## The default tool: click and Shift-click to select, drag on empty space for a box selection,
## drag a selected entity to move the selection (with snapping), drag a handle to reshape a
## wall vertex or resize a grey block (SRD FR-EDIT-1). Each gesture is one undo step.

enum Mode { IDLE, BOX, MOVE, HANDLE, TRANSFORM }

var _mode: Mode = Mode.IDLE
var _target_id: String = ""
var _press_snap: Vector2 = Vector2.ZERO
var _delta: Vector2i = Vector2i.ZERO
var _collapse_on_release: bool = false
var _box: Rect2 = Rect2()
var _box_start: Vector2 = Vector2.ZERO
var _handle: Dictionary = {}
var _handle_props: Dictionary = {}
# transform-box gesture (Affinity-style resize and rotation)
var _t_handle: String = ""
var _t_original: Rect2 = Rect2()
var _t_grab: Vector2 = Vector2.ZERO
var _t_entities: Array[Entity] = []
var _t_followers: Array = []
var _t_props: Dictionary = {}


func tool_name() -> String:
	return "select"


func is_active() -> bool:
	return _mode != Mode.IDLE


## Vertex handles shown for a single selected wall. Each is {"pos": Vector2, "kind": "vertex",
## "index": int, "entity": id}. Resizing and rotating go through the transform box instead.
static func handles_for(model: EditorModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if model.selection.size() != 1:
		return out
	var entity: Entity = model.selected_entities()[0]
	if entity.type == "wall":
		var points: Array = entity.props["points"]
		for i: int in points.size():
			out.append({"pos": EntityGeometry.vec(points[i]), "kind": "vertex", "index": i, "entity": entity.id})
	return out


## The transform box around the current selection, or null when nothing is selected.
static func box_for(model: EditorModel) -> TransformBox:
	if model.selection.is_empty():
		return null
	return TransformBox.make(model.selection_bounds(true), model.view().zoom)


func press(model: EditorModel, input: ToolInput) -> void:
	var handle: Dictionary = _handle_at(model, input.world, input.tolerance)
	if not handle.is_empty():
		_mode = Mode.HANDLE
		_handle = handle
		_target_id = str(handle["entity"])
		_handle_props = {}
		model.changed.emit()
		return
	var box: TransformBox = SelectTool.box_for(model)
	if box != null:
		var box_handle: String = box.hit(input.world, input.tolerance * 0.7)
		if not box_handle.is_empty():
			_begin_transform(model, box, box_handle, input.world)
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
		Mode.TRANSFORM:
			_update_transform(model, input)
		Mode.IDLE:
			model.hover_handle = _hover_handle(model, input)
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
	if finished == Mode.TRANSFORM:
		model.apply_transform(_t_props)
	_clear_transform()
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
	_clear_transform()
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
	elif _mode == Mode.TRANSFORM:
		return _t_props
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
	return entity.props.duplicate(true)


# --- transform box (resize and rotate handles) -------------------------------------------------


func _begin_transform(model: EditorModel, box: TransformBox, handle_id: String, grab: Vector2) -> void:
	_mode = Mode.TRANSFORM
	_t_handle = handle_id
	_t_original = box.original
	_t_grab = grab
	var expanded: Dictionary = SelectionTransform.with_followers(model.sheet(), model.selection)
	_t_followers = expanded["followers"]
	_t_entities = []
	var ids: Array = expanded["ids"]
	for raw_id: Variant in ids:
		var entity_id: String = str(raw_id)
		var entity: Entity = model.sheet().entities[entity_id]
		_t_entities.append(entity)
	_t_props = {}
	model.changed.emit()


func _update_transform(model: EditorModel, input: ToolInput) -> void:
	var ctx: RenderContext = model.ctx()
	if _t_handle == "rotate":
		var pivot: Vector2 = _t_original.get_center()
		var angle: float = TransformBox.drag_rotation(pivot, _t_grab, input.world, input.shift)
		_t_props = SelectionTransform.rotate(_t_entities, pivot, angle)
		return
	# snap the point that the dragged handle stands for, then keep the grab offset
	var moving: Vector2 = TransformBox.moving_point(_t_handle, _t_original)
	var target: Vector2 = moving + (input.world - _t_grab)
	var snapped: Vector2 = model.snap(target, model.selection).pos
	var cursor: Vector2 = _t_grab + (snapped - moving)
	var factors: Dictionary = TransformBox.drag_scale(_t_handle, _t_original, _t_grab, cursor, input.shift, input.alt)
	var anchor: Vector2 = factors["anchor"]
	var sx: float = factors["sx"]
	var sy: float = factors["sy"]
	_t_props = SelectionTransform.scale(_t_entities, ctx, anchor, sx, sy, _t_followers)


func _clear_transform() -> void:
	_t_handle = ""
	_t_entities = []
	_t_followers = []
	_t_props = {}


## Id of the handle under the pointer ("vertex" for a wall vertex), or "".
func _hover_handle(model: EditorModel, input: ToolInput) -> String:
	if not _handle_at(model, input.world, input.tolerance).is_empty():
		return "vertex"
	var box: TransformBox = SelectTool.box_for(model)
	if box == null:
		return ""
	return box.hit(input.world, input.tolerance * 0.7)
