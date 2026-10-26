class_name AnchorRules
extends RefCounted
## Anchoring (SRD FR-STACK): a symbol may be anchored to another symbol on the same étage, which
## makes a stack (a socket low, a switch at waist height, a lamp high) that moves as one.
##
## The invariant, enforced by the commands and checked when a file is loaded:
##   anchor_offset == pos - parent.pos, the parent exists, is a symbol on the same étage, is not the
##   symbol itself, and there is no cycle. An unanchored symbol has an empty parent and a zero offset.


## Returns "" when every anchor in the sheet is sound after applying `proposed` ({id: {"type", "props"}},
## new or changed entities) and removing `removed` ids; otherwise a message.
static func check(sheet: Sheet, proposed: Dictionary = {}, removed: Array = []) -> String:
	var symbols: Dictionary = {}
	var others: Dictionary = {}
	for entity_id: String in sheet.sorted_entity_ids():
		if removed.has(entity_id) or proposed.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		if entity.type == "symbol":
			symbols[entity_id] = entity.props
		else:
			others[entity_id] = true
	for key: Variant in proposed.keys():
		var entity_id: String = str(key)
		if removed.has(entity_id):
			continue
		var entry: Dictionary = proposed[key]
		if entry["type"] == "symbol":
			symbols[entity_id] = entry["props"]
		else:
			others[entity_id] = true

	var ids: Array = symbols.keys()
	ids.sort()
	for raw_id: Variant in ids:
		var entity_id: String = str(raw_id)
		var props: Dictionary = symbols[entity_id]
		var parent: String = props["anchor_parent"]
		var offset: Array = props["anchor_offset"]
		if parent.is_empty():
			if offset != [0, 0]:
				return "symbol %s is not anchored but has an anchor offset" % entity_id
			continue
		if parent == entity_id:
			return "symbol %s cannot be anchored to itself" % entity_id
		if not symbols.has(parent):
			if others.has(parent):
				return "symbol %s: its anchor parent %s is not a symbol" % [entity_id, parent]
			return "symbol %s: anchor parent %s does not exist on this étage" % [entity_id, parent]
		var parent_props: Dictionary = symbols[parent]
		var here: Vector2 = EntityGeometry.vec(props["pos"])
		var there: Vector2 = EntityGeometry.vec(parent_props["pos"])
		var expected: Vector2 = here - there
		if EntityGeometry.vec(offset) != expected:
			return "symbol %s: anchor offset %s does not match its position relative to %s (%s)" % [entity_id, str(offset), parent, str(expected)]
		# walk up: a repeated id means a cycle
		var seen: Dictionary = {entity_id: true}
		var current: String = parent
		while not current.is_empty():
			if seen.has(current):
				return "anchoring %s would make a cycle" % entity_id
			seen[current] = true
			var up: Dictionary = symbols[current]
			current = up["anchor_parent"]
			if not current.is_empty() and not symbols.has(current):
				break
	return ""


## Ids (sorted) of every symbol anchored, directly or through a chain, to one of `ids`, not counting
## the ids themselves.
static func descendants(sheet: Sheet, ids: Array) -> Array[String]:
	var children: Dictionary = {}
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if entity.type != "symbol":
			continue
		var parent: String = entity.props["anchor_parent"]
		if not parent.is_empty():
			if not children.has(parent):
				children[parent] = []
			var list: Array = children[parent]
			list.append(entity_id)
	var skip: Dictionary = {}
	for raw_id: Variant in ids:
		skip[str(raw_id)] = true
	var found: Dictionary = {}
	var queue: Array = []
	for raw_id: Variant in ids:
		queue.append(str(raw_id))
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if not children.has(current):
			continue
		var list: Array = children[current]
		for raw_child: Variant in list:
			var child: String = str(raw_child)
			if not found.has(child) and not skip.has(child):
				found[child] = true
				queue.append(child)
	var out: Array[String] = []
	for key: Variant in found.keys():
		out.append(str(key))
	out.sort()
	return out


## `props_by_id` ({id: complete new props}) with every anchored symbol's offset recomputed from the
## positions that will be in force: a parent's position comes from the map when it is in it, else
## from the sheet. Used after a transform (rotate, scale) moved positions around.
static func recompute_offsets(sheet: Sheet, props_by_id: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in props_by_id.keys():
		var entity_id: String = str(key)
		var props: Dictionary = props_by_id[key]
		var parent: String = props.get("anchor_parent", "")
		if parent.is_empty():
			out[entity_id] = props
			continue
		var parent_props: Dictionary = {}
		if props_by_id.has(parent):
			parent_props = props_by_id[parent]
		elif sheet.entities.has(parent):
			parent_props = sheet.entities[parent].props
		if parent_props.is_empty():
			out[entity_id] = props
			continue
		var fixed: Dictionary = props.duplicate(true)
		var delta: Vector2 = EntityGeometry.vec(props["pos"]) - EntityGeometry.vec(parent_props["pos"])
		fixed["anchor_offset"] = [roundi(delta.x), roundi(delta.y)]
		out[entity_id] = fixed
	return out
