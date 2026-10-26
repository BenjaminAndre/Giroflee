class_name Entity
extends RefCounted
## A drawable object on a plan sheet: id + type + props (JSON-shaped, validated by Schema).

var id: String
var type: String
var props: Dictionary


func _init(p_id: String, p_type: String, p_props: Dictionary) -> void:
	id = p_id
	type = p_type
	props = p_props


## {"type", "props"}: the form used inside patch operations.
func snapshot() -> Dictionary:
	return {"type": type, "props": props.duplicate(true)}


func to_dict() -> Dictionary:
	return {"id": id, "type": type, "props": props.duplicate(true)}
