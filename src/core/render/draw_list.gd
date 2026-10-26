class_name DrawList
extends RefCounted
## Ordered list of DrawOp: the single description of a sheet that the screen, SVG, PDF and
## PNG backends all consume (SRD ARCH-12), so on-screen equals exported.

var ops: Array[DrawOp] = []


func add(op: DrawOp) -> void:
	ops.append(op)


func append_list(other: DrawList) -> void:
	ops.append_array(other.ops)


func count_layer(layer: String) -> int:
	var n: int = 0
	for op: DrawOp in ops:
		if op.layer == layer:
			n += 1
	return n


func ops_for_entity(entity_id: String) -> Array[DrawOp]:
	var result: Array[DrawOp] = []
	for op: DrawOp in ops:
		if op.entity_id == entity_id:
			result.append(op)
	return result
