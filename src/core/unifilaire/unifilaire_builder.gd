class_name UnifilaireBuilder
extends RefCounted
## Derives the unifilaire from the document (SRD 8.1, FR-UNI-3 to FR-UNI-6). Pure and deterministic.

const TITLE_LABELS: int = 2


static func derive(doc: Document) -> UniModel:
	var model: UniModel = UniModel.new()
	var library: SymbolLibrary = SymbolLibrary.for_pack(doc.pack_ref)
	var catalog: Catalog = Catalog.for_pack(doc.pack_ref)

	# circuit -> index -> symbols
	var by_circuit: Dictionary = {}
	var unnumbered: int = 0
	for item: Dictionary in Numbering.circuit_symbols(doc):
		var entity: Entity = item["entity"]
		var index: int = entity.props["index"]
		if index <= 0:
			unnumbered += 1
			continue
		var letter: String = entity.props["circuit"]
		if not by_circuit.has(letter):
			by_circuit[letter] = {}
		var groups: Dictionary = by_circuit[letter]
		if not groups.has(index):
			groups[index] = []
		var members: Array = groups[index]
		members.append(entity)
	if unnumbered > 0:
		model.warnings.append("%d symbole(s) avec un circuit mais sans indice ne figurent pas dans l'unifilaire" % unnumbered)

	_order_bus(doc, catalog, by_circuit, model)
	for column: UniModel.Column in model.columns:
		_fill_column(doc, library, catalog, by_circuit, column)
	for raw: Variant in _board_list(doc, "head"):
		var entry: Dictionary = raw
		model.head.append({"id": str(entry.get("id", "")), "catalog": str(entry.get("catalog", ""))})

	var highest: int = 0
	for column: UniModel.Column in model.columns:
		highest = maxi(highest, column.highest_index())
	model.rows = maxi(catalog.min_rows, highest)
	return model


## The circuit columns and devices in bus order; circuits in use but not listed follow in letter order.
static func _order_bus(doc: Document, catalog: Catalog, by_circuit: Dictionary, model: UniModel) -> void:
	var placed: Dictionary = {}
	for raw: Variant in _board_list(doc, "bus"):
		var entry: Dictionary = raw
		var item: UniModel.BusItem = UniModel.BusItem.new()
		if str(entry.get("type", "device")) == "circuit":
			var letter: String = str(entry.get("letter", ""))
			if placed.has(letter):
				continue
			placed[letter] = true
			item.column = _add_column(model, letter, true)
		else:
			item.is_device = true
			item.id = str(entry.get("id", ""))
			item.catalog = str(entry.get("catalog", ""))
		model.bus.append(item)
	var rest: Array = by_circuit.keys()
	rest.sort()
	for raw_letter: Variant in rest:
		var letter: String = str(raw_letter)
		if placed.has(letter):
			continue
		var appended: UniModel.BusItem = UniModel.BusItem.new()
		appended.column = _add_column(model, letter, false)
		model.bus.append(appended)


static func _add_column(model: UniModel, letter: String, in_bus: bool) -> int:
	var column: UniModel.Column = UniModel.Column.new()
	column.letter = letter
	column.in_bus = in_bus
	model.columns.append(column)
	return model.columns.size() - 1


static func _fill_column(doc: Document, library: SymbolLibrary, catalog: Catalog, by_circuit: Dictionary, column: UniModel.Column) -> void:
	var stored: Dictionary = {}
	if doc.circuits.has(column.letter):
		stored = doc.circuits[column.letter]
	column.breaker_defaulted = not stored.has("breaker")
	column.breaker = str(stored["breaker"]) if stored.has("breaker") else catalog.default_for("breaker")
	column.cable_defaulted = not stored.has("cable")
	column.cable = str(stored["cable"]) if stored.has("cable") else catalog.default_for("cable")
	var groups: Dictionary = by_circuit.get(column.letter, {})
	column.spare = groups.is_empty()
	var typed: String = str(stored.get("title", ""))
	if not typed.is_empty():
		column.title = typed
	else:
		column.title = proposed_title(doc, column.letter)
		column.title_proposed = not column.title.is_empty()
	for key: Variant in groups.keys():
		var index: int = key
		var members: Array = groups[key]
		column.points[index] = _build_point(library, index, members)


static func _build_point(library: SymbolLibrary, index: int, members: Array) -> UniModel.Point:
	var point: UniModel.Point = UniModel.Point.new()
	point.index = index
	var entities: Array[Entity] = []
	for raw: Variant in members:
		var entity: Entity = raw
		entities.append(entity)
	# controls first, then consumers; pack order within a role, then id
	entities.sort_custom(func(a: Entity, b: Entity) -> bool:
		var ra: int = 0 if _role_of(library, a) == "control" else 1
		var rb: int = 0 if _role_of(library, b) == "control" else 1
		if ra != rb:
			return ra < rb
		var ta: int = library.order.find(str(a.props["symbol_type"]))
		var tb: int = library.order.find(str(b.props["symbol_type"]))
		if ta != tb:
			return ta < tb
		return a.id < b.id)
	for entity: Entity in entities:
		var type: String = entity.props["symbol_type"]
		var role: String = _role_of(library, entity)
		var count: int = entity.props["count"]
		point.symbol_ids.append(entity.id)
		if role == "control":
			point.has_control = true
		else:
			point.has_consumer = true
		var last: UniModel.Item = point.items[point.items.size() - 1] if not point.items.is_empty() else null
		if last != null and last.type == type:
			last.count += count
			last.ids.append(entity.id)
			continue
		var item: UniModel.Item = UniModel.Item.new()
		item.type = type
		item.role = role
		item.count = count
		item.ids.append(entity.id)
		point.items.append(item)
	point.symbol_ids.sort()
	return point


static func _role_of(library: SymbolLibrary, entity: Entity) -> String:
	var def: SymbolLibrary.Def = library.def(str(entity.props["symbol_type"]))
	return def.role if def != null else "consumer"


static func _board_list(doc: Document, key: String) -> Array:
	var value: Variant = doc.board.get(key, [])
	if value is Array:
		var list: Array = value
		return list
	return []


## Title proposed from the room labels nearest to the circuit's symbols: the most frequent ones,
## at most two, joined by " / " (SRD FR-UNI-5). "" when the plans have no room label.
static func proposed_title(doc: Document, letter: String) -> String:
	var tally: Dictionary = {}
	for sheet_id: String in doc.plan_ids():
		var sheet: Sheet = doc.get_sheet(sheet_id)
		var rooms: Array[Entity] = []
		for entity_id: String in sheet.sorted_entity_ids():
			var entity: Entity = sheet.entities[entity_id]
			if entity.type == "text" and entity.props["role"] == "room" and not str(entity.props["text"]).strip_edges().is_empty():
				rooms.append(entity)
		if rooms.is_empty():
			continue
		for entity_id: String in sheet.sorted_entity_ids():
			var symbol: Entity = sheet.entities[entity_id]
			if symbol.type != "symbol" or symbol.props["circuit"] != letter:
				continue
			var at: Vector2 = EntityGeometry.vec(symbol.props["pos"])
			var nearest: Entity = null
			var best: float = INF
			for room: Entity in rooms:
				var distance: float = at.distance_to(EntityGeometry.vec(room.props["pos"]))
				if distance < best:
					best = distance
					nearest = room
			var name: String = str(nearest.props["text"]).strip_edges()
			var seen: int = tally.get(name, 0)
			tally[name] = seen + 1
	var names: Array = tally.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ca: int = tally[a]
		var cb: int = tally[b]
		if ca != cb:
			return ca > cb
		return str(a) < str(b))
	var picked: PackedStringArray = PackedStringArray()
	for name: Variant in names:
		if picked.size() >= TITLE_LABELS:
			break
		picked.append(str(name))
	return " / ".join(picked)
