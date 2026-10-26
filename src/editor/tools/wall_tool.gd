class_name WallTool
extends Tool
## Draws walls as polylines. Click adds a point (orthogonal to the previous one unless Shift is
## held); a double-click or Enter finishes; clicking the first point closes the loop;
## Backspace removes the last point; Esc cancels (SRD FR-PLAN-3).

var points: Array[Vector2] = []
var _hover: Vector2 = Vector2.ZERO
var _has_hover: bool = false


func tool_name() -> String:
	return "wall"


func is_active() -> bool:
	return not points.is_empty()


func press(model: EditorModel, input: ToolInput) -> void:
	var p: Vector2 = _next_point(model, input)
	if not points.is_empty() and p == points[points.size() - 1]:
		if input.double_click:
			_finish(model)
		return
	points.append(p)
	if points.size() >= 3 and p == points[0]:
		_finish(model)
	elif input.double_click and points.size() >= 2:
		_finish(model)
	model.changed.emit()


func move(model: EditorModel, input: ToolInput) -> void:
	_hover = _next_point(model, input)
	_has_hover = true
	model.changed.emit()


func key(model: EditorModel, event: InputEventKey) -> bool:
	if points.is_empty():
		return false
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_finish(model)
		return true
	if event.keycode == KEY_BACKSPACE:
		points.pop_back()
		model.changed.emit()
		return true
	return false


func cancel(model: EditorModel) -> bool:
	if points.is_empty():
		return false
	points.clear()
	_has_hover = false
	model.changed.emit()
	return true


func preview(model: EditorModel) -> DrawList:
	var list: DrawList = DrawList.new()
	var path: Array = []
	for p: Vector2 in points:
		path.append([roundi(p.x), roundi(p.y)])
	if _has_hover and not points.is_empty():
		path.append([roundi(_hover.x), roundi(_hover.y)])
	if path.size() < 2:
		return list
	var context: RenderContext = model.ctx()
	var weight_page: float = model.doc().config["wall_weight_mm"]
	var weight: float = context.page_to_world(weight_page)
	for polygon: PackedVector2Array in EntityGeometry.wall_polygons(path, weight):
		var op: DrawOp = DrawOp.polygon(polygon, Color(0.05, 0.47, 0.95, 0.55), "preview")
		list.add(op)
	var a: Vector2 = EntityGeometry.vec(path[path.size() - 2])
	var b: Vector2 = EntityGeometry.vec(path[path.size() - 1])
	var size: float = 13.0 / model.view().zoom
	var readout: DrawOp = DrawOp.label(Fmt.length(a.distance_to(b)), (a + b) * 0.5 + Vector2(0.0, size * 0.8), size, PlanTheme.BLUE, "preview")
	readout.anchor = "center"
	list.add(readout)
	return list


func hint(_model: EditorModel) -> String:
	if points.is_empty():
		return "Mur : cliquez pour tracer, double-clic ou Entrée pour terminer, Maj pour un angle libre"
	return "Mur : clic = point suivant, double-clic / Entrée = terminer, Retour arrière = annuler le dernier point, Échap = abandonner"


func _next_point(model: EditorModel, input: ToolInput) -> Vector2:
	var snapped: Vector2 = model.snap(input.world).pos
	if not points.is_empty() and not input.shift:
		snapped = SnapEngine.orthogonal(points[points.size() - 1], snapped)
	return snapped


func _finish(model: EditorModel) -> void:
	if points.size() >= 2:
		var path: Array = []
		for p: Vector2 in points:
			path.append([roundi(p.x), roundi(p.y)])
		var weight: float = model.doc().config["wall_weight_mm"]
		var id: String = model.new_id()
		model.add_entities([{"id": id, "type": "wall", "props": {"points": path, "weight_mm": weight}}])
	points.clear()
	_has_hover = false
	model.changed.emit()
