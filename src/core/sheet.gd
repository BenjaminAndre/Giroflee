class_name Sheet
extends RefCounted
## One tab: an étage plan or the unifilaire. Only plan sheets hold entities.

var id: String
var kind: String
var props: Dictionary
## Entity id -> Entity. Iterate through `sorted_entity_ids()` when order matters.
var entities: Dictionary = {}


func _init(p_id: String, p_kind: String, p_props: Dictionary) -> void:
	id = p_id
	kind = p_kind
	props = p_props


func display_name() -> String:
	return str(props.get("name", ""))


## {"kind", "props"}: the form used inside patch operations.
func meta() -> Dictionary:
	return {"kind": kind, "props": props.duplicate(true)}


func sorted_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in entities.keys():
		var entity_id: String = key
		ids.append(entity_id)
	ids.sort()
	return ids


func to_dict() -> Dictionary:
	var list: Array = []
	for entity_id: String in sorted_entity_ids():
		var entity: Entity = entities[entity_id]
		list.append(entity.to_dict())
	return {"id": id, "kind": kind, "props": props.duplicate(true), "entities": list}
