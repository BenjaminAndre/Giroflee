class_name EntityCommands
extends RefCounted
## Handlers for entity.add, entity.update, entity.remove, entity.move (all on one plan sheet).


## payload: {sheet, items: [{id, type, props}]}
static func add(doc: Document, payload: Dictionary) -> BuildResult:
	var sheet: Sheet = _plan_sheet(doc, payload)
	if sheet == null:
		return BuildResult.fail(_sheet_error(doc, payload))
	if not JsonUtil.has_array(payload, "items"):
		return BuildResult.fail("entity.add needs items")
	var items: Array = payload["items"]
	var ops: Array[Dictionary] = []
	var seen: Dictionary = {}
	for item: Variant in items:
		if not (item is Dictionary):
			return BuildResult.fail("each item must be an object")
		var entry: Dictionary = item
		if not JsonUtil.has_string(entry, "id") or not JsonUtil.has_string(entry, "type"):
			return BuildResult.fail("each item needs id and type")
		var entity_id: String = entry["id"]
		var type: String = entry["type"]
		if entity_id.is_empty():
			return BuildResult.fail("entity id must not be empty")
		if doc.has_entity(entity_id) or seen.has(entity_id):
			return BuildResult.fail("entity %s already exists" % entity_id)
		if not Schema.has_entity_type(type):
			return BuildResult.fail("unknown entity type '%s'" % type)
		var raw_props: Dictionary = {}
		if entry.has("props"):
			if not (entry["props"] is Dictionary):
				return BuildResult.fail("props must be an object")
			raw_props = entry["props"]
		var normalized: Dictionary = Schema.normalize(Schema.entity_spec(type), raw_props, true)
		if not JsonUtil.flag(normalized, "ok"):
			return BuildResult.fail("entity %s: %s" % [entity_id, str(normalized["error"])])
		var props: Dictionary = normalized["props"]
		var problem: String = Schema.check_entity(type, props)
		if not problem.is_empty():
			return BuildResult.fail("entity %s: %s" % [entity_id, problem])
		seen[entity_id] = true
		ops.append(Patch.entity_op(sheet.id, entity_id, null, {"type": type, "props": props}))
	return BuildResult.success(ops)


## payload: {sheet, items: [{id, props: {partial}}]}
static func update(doc: Document, payload: Dictionary) -> BuildResult:
	var sheet: Sheet = _plan_sheet(doc, payload)
	if sheet == null:
		return BuildResult.fail(_sheet_error(doc, payload))
	if not JsonUtil.has_array(payload, "items"):
		return BuildResult.fail("entity.update needs items")
	var items: Array = payload["items"]
	var ops: Array[Dictionary] = []
	var seen: Dictionary = {}
	for item: Variant in items:
		if not (item is Dictionary):
			return BuildResult.fail("each item must be an object")
		var entry: Dictionary = item
		if not JsonUtil.has_string(entry, "id") or not JsonUtil.has_dict(entry, "props"):
			return BuildResult.fail("each item needs id and props")
		var entity_id: String = entry["id"]
		if seen.has(entity_id):
			return BuildResult.fail("entity %s listed twice" % entity_id)
		if not sheet.entities.has(entity_id):
			return BuildResult.fail("entity %s is not on sheet %s" % [entity_id, sheet.id])
		seen[entity_id] = true
		var entity: Entity = sheet.entities[entity_id]
		var raw_props: Dictionary = entry["props"]
		var normalized: Dictionary = Schema.normalize(Schema.entity_spec(entity.type), raw_props, false)
		if not JsonUtil.flag(normalized, "ok"):
			return BuildResult.fail("entity %s: %s" % [entity_id, str(normalized["error"])])
		var patch_props: Dictionary = normalized["props"]
		var merged: Dictionary = entity.props.duplicate(true)
		merged.merge(patch_props, true)
		var problem: String = Schema.check_entity(entity.type, merged)
		if not problem.is_empty():
			return BuildResult.fail("entity %s: %s" % [entity_id, problem])
		if merged != entity.props:
			ops.append(Patch.entity_op(sheet.id, entity_id, entity.snapshot(), {"type": entity.type, "props": merged}))
	return BuildResult.success(ops)


## payload: {sheet, ids: [id]}
static func remove(doc: Document, payload: Dictionary) -> BuildResult:
	var sheet: Sheet = _plan_sheet(doc, payload)
	if sheet == null:
		return BuildResult.fail(_sheet_error(doc, payload))
	var check: String = _check_ids(sheet, payload)
	if not check.is_empty():
		return BuildResult.fail(check)
	var ids: Array = payload["ids"]
	var ops: Array[Dictionary] = []
	var removed: Dictionary = {}
	for raw_id: Variant in ids:
		var entity_id: String = raw_id
		var entity: Entity = sheet.entities[entity_id]
		removed[entity_id] = true
		ops.append(Patch.entity_op(sheet.id, entity_id, entity.snapshot(), null))
	# openings that stay but lose their host wall become free-standing (no dangling reference)
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if removed.has(entity_id) or entity.type != "opening":
			continue
		var host: String = entity.props["host_wall"]
		if not host.is_empty() and removed.has(host):
			var freed: Dictionary = entity.props.duplicate(true)
			freed["host_wall"] = ""
			freed["host_offset_mm"] = 0
			ops.append(Patch.entity_op(sheet.id, entity_id, entity.snapshot(), {"type": entity.type, "props": freed}))
	return BuildResult.success(ops)


## payload: {sheet, ids: [id], delta: [dx, dy]} (integer millimetres)
static func move(doc: Document, payload: Dictionary) -> BuildResult:
	var sheet: Sheet = _plan_sheet(doc, payload)
	if sheet == null:
		return BuildResult.fail(_sheet_error(doc, payload))
	var check: String = _check_ids(sheet, payload)
	if not check.is_empty():
		return BuildResult.fail(check)
	var delta: Dictionary = Schema.coerce("vec2i", payload.get("delta"))
	if not JsonUtil.flag(delta, "ok"):
		return BuildResult.fail("delta: %s" % str(delta["error"]))
	var d: Array = delta["value"]
	var dx: int = d[0]
	var dy: int = d[1]
	var requested: Array = payload["ids"]
	var ids: Array = _with_hosted_openings(sheet, requested)
	var ops: Array[Dictionary] = []
	if dx == 0 and dy == 0:
		return BuildResult.success(ops)
	for raw_id: Variant in ids:
		var entity_id: String = raw_id
		var entity: Entity = sheet.entities[entity_id]
		var moved: Dictionary = EntityMover.shifted_props(entity.type, entity.props, dx, dy)
		ops.append(Patch.entity_op(sheet.id, entity_id, entity.snapshot(), {"type": entity.type, "props": moved}))
	return BuildResult.success(ops)


## `ids` plus the openings hosted by any wall in `ids` (they move with their wall, SRD 5.1),
## without duplicates. Added ids come in sorted order, so the result is deterministic.
static func _with_hosted_openings(sheet: Sheet, ids: Array) -> Array:
	var result: Array = ids.duplicate()
	var present: Dictionary = {}
	for raw_id: Variant in ids:
		present[raw_id] = true
	for entity_id: String in sheet.sorted_entity_ids():
		if present.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		if entity.type != "opening":
			continue
		var host: String = entity.props["host_wall"]
		if not host.is_empty() and present.has(host):
			result.append(entity_id)
	return result


static func _plan_sheet(doc: Document, payload: Dictionary) -> Sheet:
	if not JsonUtil.has_string(payload, "sheet"):
		return null
	var sheet: Sheet = doc.get_sheet(str(payload["sheet"]))
	if sheet == null or sheet.kind != "plan":
		return null
	return sheet


static func _sheet_error(doc: Document, payload: Dictionary) -> String:
	if not JsonUtil.has_string(payload, "sheet"):
		return "payload needs a sheet id"
	var sheet_id: String = payload["sheet"]
	var sheet: Sheet = doc.get_sheet(sheet_id)
	if sheet == null:
		return "sheet %s does not exist" % sheet_id
	return "sheet %s is not a plan sheet" % sheet_id


## Validates payload.ids: a list of distinct ids that all exist on the sheet.
static func _check_ids(sheet: Sheet, payload: Dictionary) -> String:
	if not JsonUtil.has_array(payload, "ids"):
		return "payload needs ids"
	var ids: Array = payload["ids"]
	var seen: Dictionary = {}
	for raw_id: Variant in ids:
		if not (raw_id is String):
			return "ids must be strings"
		var entity_id: String = raw_id
		if seen.has(entity_id):
			return "entity %s listed twice" % entity_id
		if not sheet.entities.has(entity_id):
			return "entity %s is not on sheet %s" % [entity_id, sheet.id]
		seen[entity_id] = true
	return ""
