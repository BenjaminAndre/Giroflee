class_name Selectors
extends RefCounted
## "Select by filter" (SRD FR-EDIT-8): ids of the entities of one étage matching a condition.


static func symbols_of_circuit(sheet: Sheet, circuit: String) -> Array[String]:
	return _symbols(sheet, func(entity: Entity) -> bool: return entity.props["circuit"] == circuit)


static func symbols_of_type(sheet: Sheet, type: String) -> Array[String]:
	return _symbols(sheet, func(entity: Entity) -> bool: return entity.props["symbol_type"] == type)


## Symbols that take a circuit (by their pack type) and have none yet.
static func symbols_without_circuit(sheet: Sheet, library: SymbolLibrary) -> Array[String]:
	return _symbols(sheet, func(entity: Entity) -> bool:
		var def: SymbolLibrary.Def = library.def(str(entity.props["symbol_type"]))
		var wants: bool = def == null or def.uses_circuit
		return wants and entity.props["circuit"] == "")


## Texts with their own font or size (FR-TXT-3).
static func custom_texts(sheet: Sheet) -> Array[String]:
	var out: Array[String] = []
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if entity.type != "text":
			continue
		var size: float = entity.props["size_pt"]
		if entity.props["font"] != "" or size != 0.0:
			out.append(entity_id)
	return out


static func _symbols(sheet: Sheet, matches: Callable) -> Array[String]:
	var out: Array[String] = []
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if entity.type == "symbol" and matches.call(entity):
			out.append(entity_id)
	return out
