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


## The nine slots as plain data, for the user's preferences (a slot is {} when empty).
func to_data() -> Array:
	var out: Array = []
	for slot: Dictionary in slots:
		out.append(slot.duplicate(true))
	return out


## Replaces the slots with saved data. A slot that does not look like a preset is left empty.
func load_data(data: Variant) -> void:
	clear()
	if not (data is Array):
		return
	var list: Array = data
	for i: int in mini(list.size(), SLOTS):
		if list[i] is Dictionary:
			var raw: Dictionary = list[i]
			slots[i] = sanitize(raw)


## A preset read back from JSON (numbers come back as floats), or {} when it is not one.
static func sanitize(raw: Dictionary) -> Dictionary:
	if not (raw.get("tool") is String) or str(raw["tool"]).is_empty():
		return {}
	var defaults: Dictionary = {}
	var saved: Variant = raw.get("defaults", {})
	if saved is Dictionary:
		var source: Dictionary = saved
		for key: Variant in source.keys():
			if JsonUtil.is_integral(source[key]):
				defaults[str(key)] = JsonUtil.to_int(source[key])
	var rotation: float = JsonUtil.to_float(raw["rotation"]) if JsonUtil.is_number(raw.get("rotation")) else 0.0
	var weight: float = JsonUtil.to_float(raw["wall_weight"]) if JsonUtil.is_number(raw.get("wall_weight")) else 1.4
	var count: int = JsonUtil.to_int(raw["count"]) if JsonUtil.is_integral(raw.get("count")) else 1
	return {
		"tool": str(raw["tool"]), "rotation": rotation,
		"flip_h": JsonUtil.bool_or(raw, "flip_h", false), "flip_v": JsonUtil.bool_or(raw, "flip_v", false),
		"manual": JsonUtil.bool_or(raw, "manual", false), "count": maxi(count, 1),
		"defaults": defaults, "wall_weight": weight,
	}


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
