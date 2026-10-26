class_name SheetCommands
extends RefCounted
## Handlers for sheet.add, sheet.update, sheet.remove, sheet.move.


## payload: {id, kind, props: {name, ...}, index?}
static func add(doc: Document, payload: Dictionary) -> BuildResult:
	if not JsonUtil.has_string(payload, "id") or not JsonUtil.has_string(payload, "kind") \
			or not JsonUtil.has_dict(payload, "props"):
		return BuildResult.fail("sheet.add needs id, kind and props")
	var sheet_id: String = payload["id"]
	var kind: String = payload["kind"]
	var raw_props: Dictionary = payload["props"]
	if sheet_id.is_empty():
		return BuildResult.fail("sheet id must not be empty")
	if doc.sheets.has(sheet_id):
		return BuildResult.fail("sheet %s already exists" % sheet_id)
	if not Schema.SHEET_KINDS.has(kind):
		return BuildResult.fail("unknown sheet kind '%s'" % kind)
	var normalized: Dictionary = Schema.normalize(Schema.SHEET_SPEC, raw_props, true)
	if not JsonUtil.flag(normalized, "ok"):
		return BuildResult.fail(str(normalized["error"]))
	var props: Dictionary = normalized["props"]
	var problem: String = Schema.check_sheet(props)
	if problem.is_empty():
		problem = _check_ghosts(doc, sheet_id, props)
	if not problem.is_empty():
		return BuildResult.fail(problem)

	var before_order: Array = doc.sheet_order.duplicate()
	var index: int = before_order.size()
	if payload.has("index"):
		if not JsonUtil.is_integral(payload["index"]):
			return BuildResult.fail("index must be an integer")
		index = JsonUtil.to_int(payload["index"])
		if index < 0 or index > before_order.size():
			return BuildResult.fail("index out of range")
	var after_order: Array = before_order.duplicate()
	after_order.insert(index, sheet_id)

	var ops: Array[Dictionary] = [
		Patch.sheet_op(sheet_id, null, {"kind": kind, "props": props}),
		Patch.order_op(before_order, after_order),
	]
	return BuildResult.success(ops)


## payload: {id, props: {partial}}
static func update(doc: Document, payload: Dictionary) -> BuildResult:
	if not JsonUtil.has_string(payload, "id") or not JsonUtil.has_dict(payload, "props"):
		return BuildResult.fail("sheet.update needs id and props")
	var sheet_id: String = payload["id"]
	var sheet: Sheet = doc.get_sheet(sheet_id)
	if sheet == null:
		return BuildResult.fail("sheet %s does not exist" % sheet_id)
	var raw_props: Dictionary = payload["props"]
	var normalized: Dictionary = Schema.normalize(Schema.SHEET_SPEC, raw_props, false)
	if not JsonUtil.flag(normalized, "ok"):
		return BuildResult.fail(str(normalized["error"]))
	var patch_props: Dictionary = normalized["props"]
	var merged: Dictionary = sheet.props.duplicate(true)
	merged.merge(patch_props, true)
	var problem: String = Schema.check_sheet(merged)
	if problem.is_empty():
		problem = _check_ghosts(doc, sheet_id, merged)
	if not problem.is_empty():
		return BuildResult.fail(problem)
	var ops: Array[Dictionary] = []
	if merged != sheet.props:
		ops.append(Patch.sheet_op(sheet_id, sheet.meta(), {"kind": sheet.kind, "props": merged}))
	return BuildResult.success(ops)


## payload: {id}. Removes the sheet, its entities, and references to it from other sheets' ghosts.
static func remove(doc: Document, payload: Dictionary) -> BuildResult:
	if not JsonUtil.has_string(payload, "id"):
		return BuildResult.fail("sheet.remove needs id")
	var sheet_id: String = payload["id"]
	var sheet: Sheet = doc.get_sheet(sheet_id)
	if sheet == null:
		return BuildResult.fail("sheet %s does not exist" % sheet_id)
	var ops: Array[Dictionary] = []
	for other_id: String in doc.sheet_order:
		if other_id == sheet_id:
			continue
		var other: Sheet = doc.get_sheet(other_id)
		var ghosts: Array = other.props["ghost_sheets"]
		if ghosts.has(sheet_id):
			var kept: Array = ghosts.duplicate()
			kept.erase(sheet_id)
			var new_props: Dictionary = other.props.duplicate(true)
			new_props["ghost_sheets"] = kept
			ops.append(Patch.sheet_op(other_id, other.meta(), {"kind": other.kind, "props": new_props}))
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		ops.append(Patch.entity_op(sheet_id, entity_id, entity.snapshot(), null))
	ops.append(Patch.sheet_op(sheet_id, sheet.meta(), null))
	var before_order: Array = doc.sheet_order.duplicate()
	var after_order: Array = before_order.duplicate()
	after_order.erase(sheet_id)
	ops.append(Patch.order_op(before_order, after_order))
	return BuildResult.success(ops)


## payload: {id, index}: moves the sheet to `index` in the tab order.
static func move(doc: Document, payload: Dictionary) -> BuildResult:
	if not JsonUtil.has_string(payload, "id") or not JsonUtil.is_integral(payload.get("index")):
		return BuildResult.fail("sheet.move needs id and an integer index")
	var sheet_id: String = payload["id"]
	if doc.get_sheet(sheet_id) == null:
		return BuildResult.fail("sheet %s does not exist" % sheet_id)
	var index: int = JsonUtil.to_int(payload["index"])
	var before_order: Array = doc.sheet_order.duplicate()
	if index < 0 or index >= before_order.size():
		return BuildResult.fail("index out of range")
	var after_order: Array = before_order.duplicate()
	after_order.erase(sheet_id)
	after_order.insert(index, sheet_id)
	var ops: Array[Dictionary] = []
	if after_order != before_order:
		ops.append(Patch.order_op(before_order, after_order))
	return BuildResult.success(ops)


static func _check_ghosts(doc: Document, sheet_id: String, props: Dictionary) -> String:
	var ghosts: Array = props["ghost_sheets"]
	for ghost: Variant in ghosts:
		var ghost_id: String = ghost
		if ghost_id == sheet_id:
			return "a sheet cannot ghost itself"
		if not doc.sheets.has(ghost_id):
			return "ghost sheet %s does not exist" % ghost_id
	return ""
