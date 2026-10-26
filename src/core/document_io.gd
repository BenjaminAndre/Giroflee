class_name DocumentIO
extends RefCounted
## Reads and writes the `.giroflee` project file: plain JSON, UTF-8, keys sorted and entities
## ordered by id so that it diffs cleanly in git (SRD FR-FILE-1). Loading is strict: unknown
## keys and invalid values are errors, never silently dropped.

const TOP_LEVEL_KEYS: PackedStringArray = [
	"format_version", "pack_ref", "config", "cartouche", "board", "circuits", "sheets",
]


class LoadResult:
	extends RefCounted
	var document: Document = null
	var error: String = ""


static func to_json(doc: Document) -> String:
	return JsonWriter.stringify(doc.to_dict()) + "\n"


## Writes the project file. Returns "" on success or an error message.
static func save_file(doc: Document, path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(to_json(doc))
	file.close()
	return ""


static func load_file(path: String, registry: Dictionary = Migrations.default_registry()) -> LoadResult:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
	return from_json(file.get_as_text(), registry)


static func from_json(text: String, registry: Dictionary = Migrations.default_registry()) -> LoadResult:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _fail("not a valid project file (JSON object expected): line %d: %s" % [json.get_error_line(), json.get_error_message()])
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return _fail("not a valid project file (JSON object expected)")
	var raw: Dictionary = parsed
	return from_dict(raw, registry)


static func from_dict(raw: Dictionary, registry: Dictionary = Migrations.default_registry()) -> LoadResult:
	var migrated: Dictionary = Migrations.migrate(raw, Document.CURRENT_FORMAT_VERSION, registry)
	if not JsonUtil.flag(migrated, "ok"):
		return _fail(str(migrated["error"]))
	var data: Dictionary = migrated["data"]
	for raw_key: Variant in data.keys():
		var key: String = str(raw_key)
		if not TOP_LEVEL_KEYS.has(key):
			return _fail("unknown top-level key '%s'" % key)

	var doc: Document = Document.new()
	if not JsonUtil.has_string(data, "pack_ref"):
		return _fail("pack_ref must be a string")
	doc.pack_ref = data["pack_ref"]

	if not JsonUtil.has_dict(data, "config"):
		return _fail("config must be an object")
	var config_raw: Dictionary = data["config"]
	var config: Dictionary = Schema.normalize(Schema.CONFIG_SPEC, config_raw, true)
	if not JsonUtil.flag(config, "ok"):
		return _fail("config: %s" % str(config["error"]))
	doc.config = config["props"]
	var config_problem: String = Schema.check_config(doc.config)
	if not config_problem.is_empty():
		return _fail("config: %s" % config_problem)

	for section_name: String in Schema.FREE_SECTIONS:
		if not JsonUtil.has_dict(data, section_name):
			return _fail("%s must be an object" % section_name)
		var section: Dictionary = data[section_name]
		if not JsonUtil.is_json_value(section):
			return _fail("%s contains a value that is not JSON" % section_name)
		doc.section(section_name).merge(section.duplicate(true))

	if not JsonUtil.has_array(data, "sheets"):
		return _fail("sheets must be an array")
	var sheet_list: Array = data["sheets"]
	var seen_entities: Dictionary = {}
	for item: Variant in sheet_list:
		var error: String = _load_sheet(doc, item, seen_entities)
		if not error.is_empty():
			return _fail(error)

	var integrity: String = doc.check_integrity()
	if not integrity.is_empty():
		return _fail(integrity)
	var result: LoadResult = LoadResult.new()
	result.document = doc
	return result


static func _load_sheet(doc: Document, item: Variant, seen_entities: Dictionary) -> String:
	if not (item is Dictionary):
		return "each sheet must be an object"
	var entry: Dictionary = item
	if not JsonUtil.has_string(entry, "id") or not JsonUtil.has_string(entry, "kind") \
			or not JsonUtil.has_dict(entry, "props") or not JsonUtil.has_array(entry, "entities"):
		return "each sheet needs id, kind, props and entities"
	for raw_key: Variant in entry.keys():
		if not ["id", "kind", "props", "entities"].has(str(raw_key)):
			return "unknown sheet key '%s'" % str(raw_key)
	var sheet_id: String = entry["id"]
	var kind: String = entry["kind"]
	if sheet_id.is_empty() or doc.sheets.has(sheet_id):
		return "invalid or duplicate sheet id '%s'" % sheet_id
	if not Schema.SHEET_KINDS.has(kind):
		return "unknown sheet kind '%s'" % kind
	var raw_props: Dictionary = entry["props"]
	var normalized: Dictionary = Schema.normalize(Schema.SHEET_SPEC, raw_props, true)
	if not JsonUtil.flag(normalized, "ok"):
		return "sheet %s: %s" % [sheet_id, str(normalized["error"])]
	var props: Dictionary = normalized["props"]
	var problem: String = Schema.check_sheet(props)
	if not problem.is_empty():
		return "sheet %s: %s" % [sheet_id, problem]
	doc.put_sheet_raw(sheet_id, kind, props)
	doc.sheet_order.append(sheet_id)

	var entities: Array = entry["entities"]
	for raw_entity: Variant in entities:
		var error: String = _load_entity(doc, sheet_id, raw_entity, seen_entities)
		if not error.is_empty():
			return error
	return ""


static func _load_entity(doc: Document, sheet_id: String, item: Variant, seen: Dictionary) -> String:
	if not (item is Dictionary):
		return "each entity must be an object"
	var entry: Dictionary = item
	if not JsonUtil.has_string(entry, "id") or not JsonUtil.has_string(entry, "type") \
			or not JsonUtil.has_dict(entry, "props"):
		return "each entity needs id, type and props"
	for raw_key: Variant in entry.keys():
		if not ["id", "type", "props"].has(str(raw_key)):
			return "unknown entity key '%s'" % str(raw_key)
	var entity_id: String = entry["id"]
	var type: String = entry["type"]
	if entity_id.is_empty() or seen.has(entity_id):
		return "invalid or duplicate entity id '%s'" % entity_id
	if not Schema.has_entity_type(type):
		return "entity %s: unknown type '%s'" % [entity_id, type]
	var sheet: Sheet = doc.get_sheet(sheet_id)
	if sheet.kind != "plan":
		return "entity %s: sheet %s is not a plan sheet" % [entity_id, sheet_id]
	var raw_props: Dictionary = entry["props"]
	var normalized: Dictionary = Schema.normalize(Schema.entity_spec(type), raw_props, true)
	if not JsonUtil.flag(normalized, "ok"):
		return "entity %s: %s" % [entity_id, str(normalized["error"])]
	var props: Dictionary = normalized["props"]
	var problem: String = Schema.check_entity(type, props)
	if not problem.is_empty():
		return "entity %s: %s" % [entity_id, problem]
	seen[entity_id] = true
	doc.put_entity_raw(sheet_id, entity_id, type, props)
	return ""


static func _fail(message: String) -> LoadResult:
	var result: LoadResult = LoadResult.new()
	result.error = message
	return result
