class_name SymbolLibrary
extends RefCounted
## The symbols of a pack (SRD section 11): a folder with `pack.json`, `symbols.json` and one SVG
## file per symbol and view. Adding a country means adding a folder, no code. A pack can include
## others (loaded first) and override their symbols. A symbol that cannot be loaded is skipped
## and reported in `problems`, so one bad file never breaks the editor.

const PACKS_DIR: String = "res://packs"
const ATTACH_KINDS: PackedStringArray = ["free", "wall"]
const ROLES: PackedStringArray = ["control", "consumer"]

static var _cache: Dictionary = {}


class Def:
	extends RefCounted
	var id: String = ""
	var title: String = ""
	## Artwork on the plan (page millimetres, y down, anchor at the origin).
	var plan: SvgArt = null
	## Artwork in the unifilaire; the plan artwork when the pack has none (SRD FR-CSYM-4).
	var unifilaire: SvgArt = null
	## "free" or "wall" (a wall symbol turns to face away from the nearest wall).
	var attach: String = "free"
	## Counts as an electrical point for the circuit rules (a triple socket is one point).
	var counts_as_point: bool = true
	## Takes a circuit letter and an index (panel and meter markers do not).
	var uses_circuit: bool = true
	## Fixed text drawn on the symbol (TGBT, kWh).
	var caption: String = ""
	## A marker (board, meter): drawn in the marker colour, not part of a circuit.
	var marker: bool = false
	## "control" (a switch: it commands a consumer) or "consumer" (a lamp, a socket).
	var role: String = "consumer"


var pack_id: String = ""
var defs: Dictionary = {}
var order: PackedStringArray = PackedStringArray()
## Human-readable messages about files that could not be used.
var problems: Array[String] = []


## The library of a pack shipped under res://packs, cached.
static func for_pack(id: String) -> SymbolLibrary:
	if not _cache.has(id):
		_cache[id] = load_dir(PACKS_DIR, id)
	var lib: SymbolLibrary = _cache[id]
	return lib


## Loads pack `id` from `root`/`id` (no cache; used by tests and tools).
static func load_dir(root: String, id: String) -> SymbolLibrary:
	var lib: SymbolLibrary = SymbolLibrary.new()
	lib.pack_id = id
	lib._load_pack(root, id, [])
	return lib


func def(type: String) -> Def:
	if defs.has(type):
		var found: Def = defs[type]
		return found
	return null


func has_type(type: String) -> bool:
	return defs.has(type)


func _load_pack(root: String, id: String, chain: Array) -> void:
	if chain.has(id):
		problems.append("pack include loop: %s" % " -> ".join(PackedStringArray(chain + [id])))
		return
	var dir: String = "%s/%s" % [root, id]
	var meta: Dictionary = _read_json("%s/pack.json" % dir)
	if meta.is_empty():
		return
	var includes: Array = meta.get("includes", [])
	for included: Variant in includes:
		_load_pack(root, str(included), chain + [id])
	var table: Dictionary = _read_json("%s/symbols.json" % dir)
	if table.is_empty():
		return
	var types: Variant = table.get("types", {})
	if not (types is Dictionary):
		problems.append("%s/symbols.json: types must be an object" % dir)
		return
	var type_map: Dictionary = types
	var listed: Variant = table.get("order", type_map.keys())
	var names: Array = listed if listed is Array else type_map.keys()
	for raw_name: Variant in names:
		var type: String = str(raw_name)
		if not type_map.has(type):
			problems.append("%s/symbols.json: '%s' is in order but has no entry" % [dir, type])
			continue
		var entry: Variant = type_map[type]
		if not (entry is Dictionary):
			problems.append("%s/symbols.json: '%s' must be an object" % [dir, type])
			continue
		var entry_dict: Dictionary = entry
		var built: Def = _build_def(dir, type, entry_dict)
		if built == null:
			continue
		defs[type] = built
		if not order.has(type):
			order.append(type)


func _build_def(dir: String, type: String, entry: Dictionary) -> Def:
	var label: String = "%s/symbols.json '%s'" % [dir, type]
	for key: String in ["title", "plan"]:
		if not (entry.get(key) is String) or str(entry[key]).is_empty():
			problems.append("%s: needs a %s" % [label, key])
			return null
	var attach: String = str(entry.get("attach", "free"))
	if not ATTACH_KINDS.has(attach):
		problems.append("%s: unknown attach '%s' (free or wall)" % [label, attach])
		return null
	var role: String = str(entry.get("role", "consumer"))
	if not ROLES.has(role):
		problems.append("%s: unknown role '%s' (control or consumer)" % [label, role])
		return null
	var built: Def = Def.new()
	built.id = type
	built.role = role
	built.title = str(entry["title"])
	built.attach = attach
	built.counts_as_point = JsonUtil.bool_or(entry, "counts_as_point", true)
	built.uses_circuit = JsonUtil.bool_or(entry, "uses_circuit", true)
	built.caption = str(entry.get("caption", ""))
	built.marker = JsonUtil.bool_or(entry, "marker", false)
	built.plan = _read_art("%s/%s" % [dir, str(entry["plan"])])
	if built.plan == null:
		return null
	if entry.has("unifilaire"):
		built.unifilaire = _read_art("%s/%s" % [dir, str(entry["unifilaire"])])
		if built.unifilaire == null:
			return null
	else:
		built.unifilaire = built.plan
	return built


func _read_art(path: String) -> SvgArt:
	if not FileAccess.file_exists(path):
		problems.append("%s: file not found" % path)
		return null
	var art: SvgArt = SvgArt.parse(FileAccess.get_file_as_string(path))
	if not art.ok():
		problems.append("%s: %s" % [path, art.error])
		return null
	return art


## Parsed JSON object, or {} (with a problem recorded) when missing or malformed.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		problems.append("%s: file not found" % path)
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		problems.append("%s: not a valid JSON object" % path)
		return {}
	var data: Dictionary = json.data
	return data
