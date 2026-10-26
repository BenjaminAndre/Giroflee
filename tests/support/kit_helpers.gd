class_name TestKit
extends RefCounted
## Helpers shared by the Core tests: build sessions and populate documents quickly.


static func session(seed_value: int = 1) -> Session:
	return Session.new(InProcessChannel.new(Document.new_project()), IdGenerator.new(seed_value))


static func add_sheet(s: Session, sheet_id: String, sheet_name: String = "Rez") -> CommandResult:
	return s.run_one("sheet.add", {"id": sheet_id, "kind": "plan", "props": {"name": sheet_name}})


static func add_wall(s: Session, sheet_id: String, entity_id: String, points: Array) -> CommandResult:
	return add_entity(s, sheet_id, entity_id, "wall", {"points": points})


static func add_symbol(s: Session, sheet_id: String, entity_id: String, pos: Array, circuit: String = "A", index: int = 1, symbol_type: String = "lamp") -> CommandResult:
	var props: Dictionary = {"symbol_type": symbol_type, "pos": pos, "circuit": circuit, "index": index}
	return add_entity(s, sheet_id, entity_id, "symbol", props)


static func add_entity(s: Session, sheet_id: String, entity_id: String, type: String, props: Dictionary) -> CommandResult:
	return s.run_one("entity.add", {"sheet": sheet_id, "items": [{"id": entity_id, "type": type, "props": props}]})


static func json(doc: Document) -> String:
	return DocumentIO.to_json(doc)


static func entity_props(doc: Document, entity_id: String) -> Dictionary:
	var entity: Entity = doc.find_entity(entity_id)
	if entity == null:
		return {}
	return entity.props
