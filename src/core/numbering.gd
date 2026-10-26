class_name Numbering
extends RefCounted
## Circuit letters, point indices and points (SRD 5.2). A symbol has a circuit letter and an
## index; all symbols of the same circuit and index, on any étage, form one point (so a switch and
## its lamps are linked, and a triple socket counts once). Indices are stable: deleting a symbol
## never renumbers, and a new symbol takes the highest index of its circuit plus one; closing
## gaps is the explicit "Compacter la numérotation" command.


## Every symbol that carries a circuit: [{"sheet": String, "entity": Entity}], in sheet then id order.
static func circuit_symbols(doc: Document) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sheet_id: String in doc.sheet_order:
		var sheet: Sheet = doc.get_sheet(sheet_id)
		for entity_id: String in sheet.sorted_entity_ids():
			var entity: Entity = sheet.entities[entity_id]
			if entity.type != "symbol":
				continue
			var circuit: String = entity.props["circuit"]
			if not circuit.is_empty():
				out.append({"sheet": sheet_id, "entity": entity})
	return out


static func circuits_in_use(doc: Document) -> Array[String]:
	var seen: Dictionary = {}
	for item: Dictionary in circuit_symbols(doc):
		var entity: Entity = item["entity"]
		seen[str(entity.props["circuit"])] = true
	var out: Array[String] = []
	for key: Variant in seen.keys():
		out.append(str(key))
	out.sort()
	return out


## Highest index used in `circuit` on any étage, plus one (1 when the circuit is empty).
static func next_index(doc: Document, circuit: String) -> int:
	var highest: int = 0
	for item: Dictionary in circuit_symbols(doc):
		var entity: Entity = item["entity"]
		if entity.props["circuit"] == circuit:
			var index: int = entity.props["index"]
			highest = maxi(highest, index)
	return highest + 1


## Index -> ids (sorted) of the symbols of `circuit` sharing it. Unassigned symbols (index 0) are left out.
static func groups(doc: Document, circuit: String) -> Dictionary:
	var out: Dictionary = {}
	for item: Dictionary in circuit_symbols(doc):
		var entity: Entity = item["entity"]
		var index: int = entity.props["index"]
		if entity.props["circuit"] != circuit or index <= 0:
			continue
		if not out.has(index):
			out[index] = []
		var ids: Array = out[index]
		ids.append(entity.id)
	var sorted_keys: Array = out.keys()
	sorted_keys.sort()
	var ordered: Dictionary = {}
	for key: Variant in sorted_keys:
		var ids: Array = out[key]
		ids.sort()
		ordered[key] = ids
	return ordered


## Number of electrical points of `circuit`: groups with at least one symbol that counts as a
## point in the pack. The `count` of a symbol never matters (a triple socket is one point).
static func point_count(doc: Document, circuit: String) -> int:
	var library: SymbolLibrary = SymbolLibrary.for_pack(doc.pack_ref)
	var points: Dictionary = {}
	for item: Dictionary in circuit_symbols(doc):
		var entity: Entity = item["entity"]
		var index: int = entity.props["index"]
		if entity.props["circuit"] != circuit or index <= 0:
			continue
		var type: String = entity.props["symbol_type"]
		var def: SymbolLibrary.Def = library.def(type)
		if def == null or def.counts_as_point:
			points[index] = true
	return points.size()


## `entity.update` items per sheet that renumber one circuit (or all with "") as 1..n in the order
## of the current indices, links kept. Empty when nothing would change.
static func compact_plan(doc: Document, circuit: String = "") -> Dictionary:
	var letters: Array[String] = []
	if circuit.is_empty():
		letters = circuits_in_use(doc)
	else:
		letters.append(circuit)
	var plan: Dictionary = {}
	for letter: String in letters:
		var next: int = 1
		var groups_map: Dictionary = groups(doc, letter)
		for key: Variant in groups_map.keys():
			var old_index: int = key
			var ids: Array = groups_map[key]
			if old_index != next:
				for raw_id: Variant in ids:
					var entity_id: String = str(raw_id)
					var sheet_id: String = doc.sheet_id_of_entity(entity_id)
					if not plan.has(sheet_id):
						plan[sheet_id] = []
					var items: Array = plan[sheet_id]
					items.append({"id": entity_id, "props": {"index": next}})
			next += 1
	return plan


## `entity.update` items that move the circuit symbols among `ids` (one étage) to `new_circuit`: each
## group of the selection gets the next free index there, groups stay together, unassigned symbols
## each get their own. Walls, markers and the like are ignored.
static func reassign_items(doc: Document, sheet_id: String, ids: Array, new_circuit: String) -> Array:
	var sheet: Sheet = doc.get_sheet(sheet_id)
	var chosen: Array[Entity] = []
	if sheet != null:
		for raw_id: Variant in ids:
			var entity_id: String = str(raw_id)
			if not sheet.entities.has(entity_id):
				continue
			var entity: Entity = sheet.entities[entity_id]
			var type: String = entity.type
			if type != "symbol":
				continue
			var def: SymbolLibrary.Def = SymbolLibrary.for_pack(doc.pack_ref).def(str(entity.props["symbol_type"]))
			if def != null and not def.uses_circuit:
				continue
			chosen.append(entity)
	chosen.sort_custom(func(a: Entity, b: Entity) -> bool:
		var ca: String = a.props["circuit"]
		var cb: String = b.props["circuit"]
		if ca != cb:
			return ca < cb
		var ia: int = a.props["index"]
		var ib: int = b.props["index"]
		if ia != ib:
			return ia < ib
		return a.id < b.id)
	var next: int = next_index(doc, new_circuit)
	var assigned: Dictionary = {}
	var items: Array = []
	for entity: Entity in chosen:
		var old_circuit: String = entity.props["circuit"]
		var old_index: int = entity.props["index"]
		var key: String = "%s|%d" % [old_circuit, old_index]
		var new_index: int
		if old_index > 0 and assigned.has(key):
			new_index = assigned[key]
		else:
			new_index = next
			next += 1
			if old_index > 0:
				assigned[key] = new_index
		items.append({"id": entity.id, "props": {"circuit": new_circuit, "index": new_index}})
	return items
