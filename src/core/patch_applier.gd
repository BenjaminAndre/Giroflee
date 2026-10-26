class_name PatchApplier
extends RefCounted
## Applies patch operations to a Document. The only code allowed to mutate a Document
## (besides the loader). Atomic: if one operation fails, the earlier ones are rolled back.


## Applies `ops` in order. With `check_before`, every operation must find the document in the
## state it recorded as `before`, otherwise it is rejected (stale undo, conflicting edit).
## Returns "" on success or an error message (and leaves the document untouched).
static func apply(doc: Document, ops: Array[Dictionary], check_before: bool = true) -> String:
	for i: int in ops.size():
		var error: String = _apply_one(doc, ops[i], check_before)
		if not error.is_empty():
			for j: int in range(i - 1, -1, -1):
				_apply_one(doc, Patch.invert_op(ops[j]), false)
			return "op %d (%s): %s" % [i, str(ops[i].get("op", "?")), error]
	return ""


static func _apply_one(doc: Document, op: Dictionary, check_before: bool) -> String:
	var name: String = op["op"]
	match name:
		"entity":
			return _apply_entity(doc, op, check_before)
		"sheet":
			return _apply_sheet(doc, op, check_before)
		"sheet_order":
			return _apply_order(doc, op, check_before)
		"value":
			return _apply_value(doc, op, check_before)
	return "unknown op"


static func _apply_entity(doc: Document, op: Dictionary, check_before: bool) -> String:
	var sheet_id: String = op["sheet"]
	var entity_id: String = op["id"]
	var before: Variant = op["before"]
	var after: Variant = op["after"]
	var current: Entity = doc.find_entity(entity_id)
	if check_before:
		if before == null:
			if current != null:
				return "entity %s already exists" % entity_id
		else:
			if current == null or doc.sheet_id_of_entity(entity_id) != sheet_id:
				return "entity %s is missing from sheet %s" % [entity_id, sheet_id]
			if current.snapshot() != before:
				return "entity %s changed since the operation was recorded" % entity_id
	if after == null:
		doc.remove_entity_raw(entity_id)
		return ""
	if doc.get_sheet(sheet_id) == null:
		return "sheet %s does not exist" % sheet_id
	if current != null and doc.sheet_id_of_entity(entity_id) != sheet_id:
		return "entity %s lives in another sheet" % entity_id
	var state: Dictionary = after
	var type: String = state["type"]
	var props: Dictionary = state["props"]
	doc.put_entity_raw(sheet_id, entity_id, type, props.duplicate(true))
	return ""


static func _apply_sheet(doc: Document, op: Dictionary, check_before: bool) -> String:
	var sheet_id: String = op["id"]
	var before: Variant = op["before"]
	var after: Variant = op["after"]
	var current: Sheet = doc.get_sheet(sheet_id)
	if check_before:
		if before == null:
			if current != null:
				return "sheet %s already exists" % sheet_id
		else:
			if current == null:
				return "sheet %s does not exist" % sheet_id
			if current.meta() != before:
				return "sheet %s changed since the operation was recorded" % sheet_id
	if after == null:
		if current != null and not current.entities.is_empty():
			return "sheet %s still holds entities" % sheet_id
		doc.remove_sheet_raw(sheet_id)
		return ""
	var meta: Dictionary = after
	var kind: String = meta["kind"]
	var props: Dictionary = meta["props"]
	doc.put_sheet_raw(sheet_id, kind, props.duplicate(true))
	return ""


static func _apply_order(doc: Document, op: Dictionary, check_before: bool) -> String:
	var before: Array = op["before"]
	var after: Array = op["after"]
	if check_before and not _same_strings(doc.sheet_order, before):
		return "sheet order changed since the operation was recorded"
	doc.sheet_order.assign(after)
	return ""


static func _apply_value(doc: Document, op: Dictionary, check_before: bool) -> String:
	var section_name: String = op["section"]
	var key: String = op["key"]
	var before: Variant = op["before"]
	var after: Variant = op["after"]
	var target: Dictionary = doc.section(section_name)
	if check_before:
		if before == null:
			if target.has(key):
				return "%s.%s already exists" % [section_name, key]
		else:
			if not target.has(key) or target[key] != before:
				return "%s.%s changed since the operation was recorded" % [section_name, key]
	if after == null:
		target.erase(key)
	else:
		target[key] = JsonUtil.deep_copy(after)
	return ""


static func _same_strings(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] != b[i]:
			return false
	return true
