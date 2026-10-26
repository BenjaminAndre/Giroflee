class_name Clipboard
extends RefCounted
## Copy and paste of plan entities as JSON text with a `giroflee/1` header (SRD FR-EDIT-2), so
## a selection can travel between sheets, projects and app windows through the system clipboard.
##
## Links between copied entities are kept: an opening whose wall is part of the copy still
## follows the copied wall; a link to something that was not copied is dropped. Symbols get
## their indices reassigned on paste (SRD FR-EDIT-3).

const HEADER: String = "giroflee/1"


## Text for the clipboard. Hosted openings of copied walls come along. `ids` not on the sheet
## are ignored. Returns "" when nothing can be copied.
static func serialize(sheet: Sheet, ids: Array, include_symbols: bool = true) -> String:
	var wanted: Dictionary = {}
	for raw_id: Variant in ids:
		var entity_id: String = str(raw_id)
		if sheet.entities.has(entity_id):
			wanted[entity_id] = true
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if entity.type == "opening":
			var host: String = entity.props["host_wall"]
			if wanted.has(host):
				wanted[entity_id] = true
	for carried: String in AnchorRules.descendants(sheet, wanted.keys()):
		wanted[carried] = true
	var items: Array = []
	var origin: Variant = null
	for entity_id: String in sheet.sorted_entity_ids():
		if not wanted.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		if entity.type == "symbol" and not include_symbols:
			continue
		items.append({"key": entity_id, "type": entity.type, "props": entity.props.duplicate(true)})
		var corner: Vector2 = _min_corner(entity)
		if origin == null:
			origin = corner
		else:
			var current: Vector2 = origin
			origin = Vector2(minf(current.x, corner.x), minf(current.y, corner.y))
	if items.is_empty():
		return ""
	var o: Vector2 = origin
	var payload: Dictionary = {"format": HEADER, "origin": [roundi(o.x), roundi(o.y)], "items": items}
	return JsonWriter.stringify(payload)


## Parses clipboard text. Returns {"ok", "items", "origin", "error"}; `ok` is false for text
## that is not ours (so pasting ordinary text does nothing).
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if text.is_empty() or json.parse(text) != OK or not (json.data is Dictionary):
		return _bad("not a Giroflée selection")
	var data: Dictionary = json.data
	if data.get("format") != HEADER:
		return _bad("not a Giroflée selection")
	if not (data.get("items") is Array) or not (data.get("origin") is Array):
		return _bad("malformed selection")
	var items: Array = data["items"]
	var origin: Dictionary = Schema.coerce("vec2i", data["origin"])
	if not JsonUtil.flag(origin, "ok"):
		return _bad("malformed selection origin")
	for item: Variant in items:
		if not (item is Dictionary):
			return _bad("malformed selection item")
		var entry: Dictionary = item
		if not JsonUtil.has_string(entry, "key") or not JsonUtil.has_string(entry, "type") or not JsonUtil.has_dict(entry, "props"):
			return _bad("malformed selection item")
	return {"ok": true, "items": items, "origin": origin["value"], "error": ""}


## `entity.add` items for the parsed selection, moved so that its origin lands on `target`,
## with fresh ids from `ids`. Returns {"items": Array, "new_ids": Array[String]}. With `doc`, pasted
## symbols get fresh indices in their circuit, links between pasted symbols kept (FR-EDIT-3); without
## it they come out unassigned (index 0).
static func to_add_items(parsed: Dictionary, target: Vector2i, ids: IdGenerator, doc: Document = null) -> Dictionary:
	var items: Array = parsed["items"]
	var origin: Array = parsed["origin"]
	var ox: int = origin[0]
	var oy: int = origin[1]
	var dx: int = target.x - ox
	var dy: int = target.y - oy
	var new_ids: Dictionary = {}
	for item: Variant in items:
		var entry: Dictionary = item
		var key: String = entry["key"]
		new_ids[key] = ids.next_uuid()
	var out: Array = []
	var added: Array[String] = []
	var next_for: Dictionary = {}
	var assigned: Dictionary = {}
	for item: Variant in items:
		var entry: Dictionary = item
		var key: String = entry["key"]
		var type: String = entry["type"]
		var props: Dictionary = entry["props"]
		var moved: Dictionary = EntityMover.shifted_props(type, props, dx, dy)
		if type == "opening":
			var host: String = moved.get("host_wall", "")
			moved["host_wall"] = str(new_ids.get(host, "")) if not host.is_empty() else ""
			if str(moved["host_wall"]).is_empty():
				moved["host_offset_mm"] = 0
		if type == "symbol":
			var old_index: int = moved["index"]
			var circuit: String = moved["circuit"]
			moved["index"] = 0
			if doc != null and old_index > 0 and not circuit.is_empty():
				var link: String = "%s|%d" % [circuit, old_index]
				if not assigned.has(link):
					if not next_for.has(circuit):
						next_for[circuit] = Numbering.next_index(doc, circuit)
					var fresh: int = next_for[circuit]
					assigned[link] = fresh
					next_for[circuit] = fresh + 1
				moved["index"] = assigned[link]
			var parent: String = moved.get("anchor_parent", "")
			moved["anchor_parent"] = str(new_ids.get(parent, "")) if not parent.is_empty() else ""
			if str(moved["anchor_parent"]).is_empty():
				moved["anchor_offset"] = [0, 0]
		var new_id: String = new_ids[key]
		out.append({"id": new_id, "type": type, "props": moved})
		added.append(new_id)
	return {"items": out, "new_ids": added}


static func _min_corner(entity: Entity) -> Vector2:
	var props: Dictionary = entity.props
	if entity.type == "wall":
		var points: Array = props["points"]
		var best: Vector2 = EntityGeometry.vec(points[0])
		for point: Variant in points:
			var p: Vector2 = EntityGeometry.vec(point)
			best = Vector2(minf(best.x, p.x), minf(best.y, p.y))
		return best
	return EntityGeometry.vec(props["pos"])


static func _bad(message: String) -> Dictionary:
	return {"ok": false, "items": [], "origin": [0, 0], "error": message}
