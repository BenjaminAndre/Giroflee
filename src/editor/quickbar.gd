class_name Quickbar
extends RefCounted
## Nine slots on the keys 1-9, each holding a tool preset: the tool plus its placement settings
## (rotation, mirrors, count, door/window/stair sizes, wall weight). The active circuit is not part
## of a preset (SRD FR-QB-1). Slots are filled from the palette ("Case N…") and, for now, live only
## as long as the window (FR-QB-3 is still undecided).

const SLOTS: int = 9

var slots: Array[Dictionary] = []


func _init() -> void:
	for i: int in SLOTS:
		slots.append({})


func is_filled(slot: int) -> bool:
	return slot >= 1 and slot <= SLOTS and not slots[slot - 1].is_empty()


func preset(slot: int) -> Dictionary:
	if slot < 1 or slot > SLOTS:
		return {}
	return slots[slot - 1]


func assign(slot: int, value: Dictionary) -> void:
	if slot >= 1 and slot <= SLOTS:
		slots[slot - 1] = value


func clear() -> void:
	for i: int in SLOTS:
		slots[i] = {}


## The placement tool the editor is in, with its settings. Empty for the selection tool.
static func capture(model: EditorModel) -> Dictionary:
	if model.tool_name == "select":
		return {}
	return {
		"tool": model.tool_name,
		"rotation": model.place_rotation, "flip_h": model.place_flip_h, "flip_v": model.place_flip_v,
		"manual": model.place_rotation_manual, "count": model.place_count,
		"defaults": model.defaults.duplicate(),
		"wall_weight": model.doc().config["wall_weight_mm"],
	}


static func apply(model: EditorModel, value: Dictionary) -> void:
	var tool: String = value["tool"]
	var defaults: Dictionary = value["defaults"]
	model.set_tool(tool)
	model.place_rotation = value["rotation"]
	model.place_flip_h = value["flip_h"]
	model.place_flip_v = value["flip_v"]
	model.place_rotation_manual = value["manual"]
	model.place_count = value["count"]
	model.defaults.merge(defaults, true)
	if tool == "wall":
		var weight: float = value["wall_weight"]
		var current: float = model.doc().config["wall_weight_mm"]
		if weight != current:
			model.set_config("wall_weight_mm", weight)
	model.changed.emit()
