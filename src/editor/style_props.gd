class_name StyleProps
extends RefCounted
## Copy and paste of settings (SRD FR-EDIT-7): the style-like properties of one entity applied to
## others of the same type. Identity, position, circuit, index and anchoring are never copied.

const STYLE: Dictionary = {
	"text": ["font", "size_pt", "role"],
	"symbol": ["rotation", "flip_h", "flip_v", "count"],
	"opening": ["width_mm", "flip_h", "flip_v"],
	"stair": ["width_mm", "steps", "tread_mm", "flip_h", "flip_v"],
	"wall": ["weight_mm"],
}


## {"type", "props"} of the style properties of `entity`; empty when its type has none.
static func capture(entity: Entity) -> Dictionary:
	if not STYLE.has(entity.type):
		return {}
	var keys: Array = STYLE[entity.type]
	var props: Dictionary = {}
	for key: Variant in keys:
		props[key] = JsonUtil.deep_copy(entity.props[key])
	return {"type": entity.type, "props": props}


## `entity.update` items applying `captured` to the entities among `ids` of the same type, leaving
## out those that already match.
static func items(sheet: Sheet, ids: Array, captured: Dictionary) -> Array:
	var out: Array = []
	if captured.is_empty():
		return out
	var type: String = captured["type"]
	var style: Dictionary = captured["props"]
	for raw_id: Variant in ids:
		var entity_id: String = str(raw_id)
		if not sheet.entities.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		if entity.type != type:
			continue
		var diff: Dictionary = {}
		for key: Variant in style.keys():
			if entity.props[key] != style[key]:
				diff[key] = JsonUtil.deep_copy(style[key])
		if not diff.is_empty():
			out.append({"id": entity_id, "props": diff})
	return out
