class_name StairTool
extends Tool
## Places a parametric stair (SRD 5.1). Width, steps and tread come from the editor defaults and
## are edited afterwards in the Properties panel. R rotates, H and V flip before clicking.

var _hover: Vector2 = Vector2.ZERO
var _has_hover: bool = false


func tool_name() -> String:
	return "stair"


func press(model: EditorModel, input: ToolInput) -> void:
	model.add_entities([{"id": model.new_id(), "type": "stair", "props": placement_props(model, input.world)}])


func move(model: EditorModel, input: ToolInput) -> void:
	_hover = input.world
	_has_hover = true
	model.changed.emit()


func preview(model: EditorModel) -> DrawList:
	if not _has_hover:
		return DrawList.new()
	return Tool.entity_preview(model, "stair", placement_props(model, _hover))


func hint(_model: EditorModel) -> String:
	return "Escalier : clic pour placer · R = tourner · H / V = retourner · Échap = terminer"


func placement_props(model: EditorModel, world: Vector2) -> Dictionary:
	var p: Vector2 = model.snap(world).pos
	return {
		"pos": [roundi(p.x), roundi(p.y)],
		"width_mm": model.defaults["stair_width"],
		"steps": model.defaults["stair_steps"],
		"tread_mm": model.defaults["stair_tread"],
		"rotation": model.place_rotation,
		"flip_h": model.place_flip_h,
		"flip_v": model.place_flip_v,
	}
