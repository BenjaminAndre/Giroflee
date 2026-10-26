class_name OpeningTool
extends Tool
## Places doors and windows. Near a wall the opening attaches to it: it is aligned with the
## wall, centred on the cursor along it (50 mm steps), and records the wall as its host so it
## follows the wall later. A door swings toward the side of the cursor. H and V flip the
## placement, R rotates it when it is not on a wall (SRD FR-PLAN-4).

var kind: String = "door"
var _hover: Vector2 = Vector2.ZERO
var _has_hover: bool = false


func _init(p_kind: String = "door") -> void:
	kind = p_kind


func tool_name() -> String:
	return kind


func press(model: EditorModel, input: ToolInput) -> void:
	var props: Dictionary = placement_props(model, input.world)
	model.add_entities([{"id": model.new_id(), "type": "opening", "props": props}])


func move(model: EditorModel, input: ToolInput) -> void:
	_hover = input.world
	_has_hover = true
	model.changed.emit()


func preview(model: EditorModel) -> DrawList:
	var list: DrawList = DrawList.new()
	if not _has_hover:
		return list
	var props: Dictionary = placement_props(model, _hover)
	return Tool.entity_preview(model, "opening", props)


func hint(_model: EditorModel) -> String:
	return "%s : clic pour placer (près d'un mur, il s'y accroche) · H / V = retourner · R = tourner · Échap = terminer" % ("Porte" if kind == "door" else "Fenêtre")


## Complete, schema-valid props for an opening of this tool's kind at `world`.
func placement_props(model: EditorModel, world: Vector2) -> Dictionary:
	var width_key: String = "door_width" if kind == "door" else "window_width"
	var width: int = model.defaults[width_key]
	var props: Dictionary = {
		"kind": kind, "width_mm": width,
		"flip_h": model.place_flip_h, "flip_v": model.place_flip_v,
		"rotation": model.place_rotation, "pos": [0, 0],
	}
	var hit: WallLocator.Hit = WallLocator.locate(model.sheet(), world, model.tolerance(28.0), model.spatial())
	if hit == null:
		var p: Vector2 = model.snap(world).pos
		props["pos"] = [roundi(p.x), roundi(p.y)]
		return props
	var centre_offset: float = roundf(hit.offset_mm / 50.0) * 50.0
	var centre: Vector2 = hit.point + hit.direction * (centre_offset - hit.offset_mm)
	var start: Vector2 = centre - hit.direction * (float(width) * 0.5)
	props["pos"] = [roundi(start.x), roundi(start.y)]
	props["rotation"] = snappedf(hit.angle_deg, 0.01)
	props["host_wall"] = hit.wall_id
	props["host_offset_mm"] = roundi(centre_offset - float(width) * 0.5)
	if kind == "door" and hit.side < 0:
		props["flip_v"] = not model.place_flip_v
	return props
