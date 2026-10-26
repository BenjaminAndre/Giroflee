class_name Patch
extends RefCounted
## The result of a committed command: an ordered list of primitive operations, each carrying
## its before and after state, which is enough to invert it (undo) or replay it (redo).
##
## Operation shapes (before/after are null when absent):
##   {"op": "entity",      "sheet": id, "id": id, "before": {type, props}|null, "after": ...}
##   {"op": "sheet",       "id": id, "before": {kind, props}|null, "after": ...}
##   {"op": "sheet_order", "before": [ids], "after": [ids]}
##   {"op": "value",       "section": name, "key": key, "before": v|null, "after": v|null}

var seq: int = 0
var command_id: String = ""
var tx: String = ""
var ops: Array[Dictionary] = []


static func entity_op(sheet_id: String, entity_id: String, before: Variant, after: Variant) -> Dictionary:
	return {"op": "entity", "sheet": sheet_id, "id": entity_id, "before": before, "after": after}


static func sheet_op(sheet_id: String, before: Variant, after: Variant) -> Dictionary:
	return {"op": "sheet", "id": sheet_id, "before": before, "after": after}


static func order_op(before: Array, after: Array) -> Dictionary:
	return {"op": "sheet_order", "before": before.duplicate(), "after": after.duplicate()}


static func value_op(section: String, key: String, before: Variant, after: Variant) -> Dictionary:
	return {"op": "value", "section": section, "key": key, "before": before, "after": after}


## Operations that undo `source`: reversed order, before and after swapped.
static func invert(source: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(source.size() - 1, -1, -1):
		out.append(invert_op(source[i]))
	return out


static func invert_op(op: Dictionary) -> Dictionary:
	var copy: Dictionary = op.duplicate(true)
	copy["before"] = JsonUtil.deep_copy(op["after"])
	copy["after"] = JsonUtil.deep_copy(op["before"])
	return copy


## Structural validation of operations coming from outside (a patch.apply payload).
## Returns "" when well-formed, else a message.
static func validate_ops(raw: Array) -> String:
	for i: int in raw.size():
		var item: Variant = raw[i]
		if not (item is Dictionary):
			return "op %d is not an object" % i
		var op: Dictionary = item
		if not op.has("before") or not op.has("after"):
			return "op %d needs before and after" % i
		if op["before"] == null and op["after"] == null:
			return "op %d has neither before nor after" % i
		if not JsonUtil.has_string(op, "op"):
			return "op %d has no op name" % i
		var name: String = op["op"]
		var error: String = ""
		match name:
			"entity":
				error = _check_entity_op(op)
			"sheet":
				error = _check_sheet_op(op)
			"sheet_order":
				error = _check_order_op(op)
			"value":
				error = _check_value_op(op)
			_:
				error = "unknown op '%s'" % name
		if not error.is_empty():
			return "op %d: %s" % [i, error]
	return ""


static func _check_entity_op(op: Dictionary) -> String:
	if not JsonUtil.has_string(op, "sheet") or not JsonUtil.has_string(op, "id"):
		return "entity op needs sheet and id"
	for side: String in ["before", "after"]:
		var state: Variant = op[side]
		if state == null:
			continue
		if not (state is Dictionary):
			return "%s must be an object or null" % side
		var snapshot: Dictionary = state
		if not JsonUtil.has_string(snapshot, "type") or not JsonUtil.has_dict(snapshot, "props"):
			return "%s needs type and props" % side
		var type: String = snapshot["type"]
		if not Schema.has_entity_type(type):
			return "unknown entity type '%s'" % type
	return ""


static func _check_sheet_op(op: Dictionary) -> String:
	if not JsonUtil.has_string(op, "id"):
		return "sheet op needs id"
	for side: String in ["before", "after"]:
		var state: Variant = op[side]
		if state == null:
			continue
		if not (state is Dictionary):
			return "%s must be an object or null" % side
		var meta: Dictionary = state
		if not JsonUtil.has_string(meta, "kind") or not JsonUtil.has_dict(meta, "props"):
			return "%s needs kind and props" % side
	return ""


static func _check_order_op(op: Dictionary) -> String:
	for side: String in ["before", "after"]:
		var state: Variant = op[side]
		if not (state is Array):
			return "%s must be an array" % side
		var ids: Array = state
		for item: Variant in ids:
			if not (item is String):
				return "%s must list sheet ids" % side
	return ""


static func _check_value_op(op: Dictionary) -> String:
	if not JsonUtil.has_string(op, "section") or not JsonUtil.has_string(op, "key"):
		return "value op needs section and key"
	var section: String = op["section"]
	if not Document.VALUE_SECTIONS.has(section):
		return "unknown section '%s'" % section
	for side: String in ["before", "after"]:
		var state: Variant = op[side]
		if state != null and not JsonUtil.is_json_value(state):
			return "%s is not a JSON value" % side
	return ""
