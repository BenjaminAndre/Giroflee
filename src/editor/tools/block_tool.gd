class_name BlockTool
extends Tool
## Draws a grey block (furniture, bathtub, a zone) by dragging a rectangle.

var _start: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
var _dragging: bool = false


func tool_name() -> String:
	return "block"


func is_active() -> bool:
	return _dragging


func press(model: EditorModel, input: ToolInput) -> void:
	_start = model.snap(input.world).pos
	_current = _start
	_dragging = true
	model.changed.emit()


func move(model: EditorModel, input: ToolInput) -> void:
	if _dragging:
		_current = model.snap(input.world).pos
		model.changed.emit()


func release(model: EditorModel, input: ToolInput) -> void:
	if not _dragging:
		return
	_current = model.snap(input.world).pos
	_dragging = false
	var rect: Rect2 = Rect2(_start, _current - _start).abs()
	if rect.size.x >= 1.0 and rect.size.y >= 1.0:
		var props: Dictionary = {
			"pos": [roundi(rect.position.x), roundi(rect.position.y)],
			"size": [roundi(rect.size.x), roundi(rect.size.y)],
		}
		model.add_entities([{"id": model.new_id(), "type": "grey_block", "props": props}])
	model.changed.emit()


func cancel(model: EditorModel) -> bool:
	if not _dragging:
		return false
	_dragging = false
	model.changed.emit()
	return true


func preview(model: EditorModel) -> DrawList:
	var list: DrawList = DrawList.new()
	if not _dragging:
		return list
	var rect: Rect2 = Rect2(_start, _current - _start).abs()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return list
	var corners: PackedVector2Array = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	])
	list.add(DrawOp.polygon(corners, Color(0.8, 0.8, 0.8, 0.6), "preview"))
	var size: float = 13.0 / model.view().zoom
	var readout: DrawOp = DrawOp.label("%s × %s" % [Fmt.length(rect.size.x), Fmt.length(rect.size.y)], rect.get_center(), size, PlanTheme.BLUE, "preview")
	readout.anchor = "center"
	list.add(readout)
	return list


func hint(_model: EditorModel) -> String:
	return "Bloc gris : glissez pour tracer un rectangle · Échap = terminer"
