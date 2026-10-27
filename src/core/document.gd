class_name Document
extends RefCounted
## The project: the single source of truth. Mutated only through PatchApplier (ARCH-2).

const CURRENT_FORMAT_VERSION: int = 3
## Id of the unifilaire sheet that format 3 adds to older files.
const UNIFILAIRE_ID: String = "unifilaire"
const VALUE_SECTIONS: PackedStringArray = ["config", "cartouche", "board", "circuits"]

var pack_ref: String = "belgium"
var config: Dictionary = {}
var cartouche: Dictionary = {}
var board: Dictionary = {}
var circuits: Dictionary = {}
var sheet_order: Array[String] = []
## Bumped by every applied patch; derived caches (SpatialIndex) are keyed on it. Not saved.
var revision: int = 0
## Derived data cache: sheet id -> {"revision": int, "index": SpatialIndex}.
var spatial_cache: Dictionary = {}
## Sheet id -> Sheet.
var sheets: Dictionary = {}
## Entity id -> id of the sheet that holds it (entity ids are unique document-wide).
var _entity_sheet: Dictionary = {}


static func new_project() -> Document:
	var doc: Document = Document.new()
	doc.config = Schema.default_config()
	return doc


## Props of a new unifilaire sheet: an A3 page measured in millimetres (scale 1, SRD FR-TAB-1).
static func unifilaire_props() -> Dictionary:
	return {"name": "Unifilaire", "paper_w_mm": 420, "paper_h_mm": 297, "scale_den": 1, "grid_step_mm": 10, "ghost_sheets": []}


## Ids of the étages (plan sheets) in tab order.
func plan_ids() -> Array[String]:
	var out: Array[String] = []
	for sheet_id: String in sheet_order:
		var sheet: Sheet = sheets[sheet_id]
		if sheet.kind == "plan":
			out.append(sheet_id)
	return out


## The unifilaire sheet, or null when the document has none (scripts and tests may omit it).
func unifilaire_sheet() -> Sheet:
	for sheet_id: String in sheet_order:
		var sheet: Sheet = sheets[sheet_id]
		if sheet.kind == "unifilaire":
			return sheet
	return null


func get_sheet(sheet_id: String) -> Sheet:
	if sheets.has(sheet_id):
		var sheet: Sheet = sheets[sheet_id]
		return sheet
	return null


func has_entity(entity_id: String) -> bool:
	return _entity_sheet.has(entity_id)


## Id of the sheet holding the entity, or "".
func sheet_id_of_entity(entity_id: String) -> String:
	if _entity_sheet.has(entity_id):
		var sheet_id: String = _entity_sheet[entity_id]
		return sheet_id
	return ""


func find_entity(entity_id: String) -> Entity:
	var sheet: Sheet = get_sheet(sheet_id_of_entity(entity_id))
	if sheet == null:
		return null
	var entity: Entity = sheet.entities[entity_id]
	return entity


## Reference to one of VALUE_SECTIONS (a live dictionary, do not mutate it directly).
func section(name: String) -> Dictionary:
	match name:
		"config":
			return config
		"cartouche":
			return cartouche
		"board":
			return board
		"circuits":
			return circuits
	return {}


# --- raw mutation, used only by PatchApplier and the loader -----------------------------


func put_sheet_raw(sheet_id: String, kind: String, props: Dictionary) -> void:
	if sheets.has(sheet_id):
		var existing: Sheet = sheets[sheet_id]
		existing.props = props
	else:
		sheets[sheet_id] = Sheet.new(sheet_id, kind, props)


func remove_sheet_raw(sheet_id: String) -> void:
	sheets.erase(sheet_id)


func put_entity_raw(sheet_id: String, entity_id: String, type: String, props: Dictionary) -> void:
	var sheet: Sheet = sheets[sheet_id]
	if sheet.entities.has(entity_id):
		var existing: Entity = sheet.entities[entity_id]
		existing.type = type
		existing.props = props
	else:
		sheet.entities[entity_id] = Entity.new(entity_id, type, props)
		_entity_sheet[entity_id] = sheet_id


func remove_entity_raw(entity_id: String) -> void:
	var sheet: Sheet = get_sheet(sheet_id_of_entity(entity_id))
	if sheet != null:
		sheet.entities.erase(entity_id)
	_entity_sheet.erase(entity_id)


# --- serialisation ----------------------------------------------------------------------


## Canonical form (sorted entities); the JSON writer sorts keys, so output is stable.
func to_dict() -> Dictionary:
	var sheet_list: Array = []
	for sheet_id: String in sheet_order:
		var sheet: Sheet = sheets[sheet_id]
		sheet_list.append(sheet.to_dict())
	return {
		"format_version": CURRENT_FORMAT_VERSION,
		"pack_ref": pack_ref,
		"config": config.duplicate(true),
		"cartouche": cartouche.duplicate(true),
		"board": board.duplicate(true),
		"circuits": circuits.duplicate(true),
		"sheets": sheet_list,
	}


## Structural consistency check (used by tests and after loading). Returns "" when sound.
func check_integrity() -> String:
	if sheet_order.size() != sheets.size():
		return "sheet_order and sheets disagree"
	for sheet_id: String in sheet_order:
		if not sheets.has(sheet_id):
			return "sheet_order lists unknown sheet %s" % sheet_id
	var seen: Dictionary = {}
	for index: int in sheet_order.size():
		var listed: Sheet = sheets[sheet_order[index]]
		if listed.kind == "unifilaire" and index != 0:
			return "the unifilaire sheet must be the first sheet"
	for sheet_id: String in sheet_order:
		var sheet: Sheet = sheets[sheet_id]
		if sheet.kind != "plan" and not sheet.entities.is_empty():
			return "sheet %s is not a plan sheet but holds entities" % sheet_id
		var ghosts: Array = sheet.props.get("ghost_sheets", [])
		for ghost: Variant in ghosts:
			var ghost_id: String = ghost
			if not sheets.has(ghost_id) or ghost_id == sheet_id:
				return "sheet %s has an invalid ghost reference %s" % [sheet_id, ghost_id]
		for entity_id: String in sheet.sorted_entity_ids():
			if seen.has(entity_id):
				return "entity id %s is used twice" % entity_id
			seen[entity_id] = true
			if sheet_id_of_entity(entity_id) != sheet_id:
				return "entity index is stale for %s" % entity_id
	if seen.size() != _entity_sheet.size():
		return "entity index has stale entries"
	for sheet_id: String in sheet_order:
		var checked: Sheet = sheets[sheet_id]
		var anchor_problem: String = AnchorRules.check(checked)
		if not anchor_problem.is_empty():
			return anchor_problem
	return ""
