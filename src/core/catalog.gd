class_name Catalog
extends RefCounted
## The pack's catalogue of board equipment (SRD 11.5): breakers, differentials, cables and meters.
## It is data, loaded from `catalog.json`; the unifilaire and the board editor only name items by id.

const KINDS: PackedStringArray = ["breaker", "differential", "cable", "meter"]

static var _cache: Dictionary = {}


class Item:
	extends RefCounted
	var id: String = ""
	var kind: String = ""
	## French name shown in the editor.
	var title: String = ""
	## Text drawn on the unifilaire, and an optional second line.
	var label: String = ""
	var detail: String = ""


var pack_id: String = ""
var items: Dictionary = {}
var order: Array[String] = []
## Item ids a new circuit starts with: {"breaker": id, "cable": id}.
var circuit_defaults: Dictionary = {}
## Item ids of the usual head chain, from the meter to the main breaker.
var usual_head: Array[String] = []
## Rows the row ruler always shows, however few points the circuits have.
var min_rows: int = 8
var problems: Array[String] = []


static func for_pack(id: String) -> Catalog:
	if not _cache.has(id):
		_cache[id] = load_dir(SymbolLibrary.PACKS_DIR, id)
	var found: Catalog = _cache[id]
	return found


static func load_dir(root: String, id: String) -> Catalog:
	var catalog: Catalog = Catalog.new()
	catalog.pack_id = id
	catalog._load("%s/%s/catalog.json" % [root, id])
	return catalog


func item(id: String) -> Item:
	if items.has(id):
		var found: Item = items[id]
		return found
	return null


## The items of one kind, in file order.
func items_of(kind: String) -> Array[Item]:
	var out: Array[Item] = []
	for item_id: String in order:
		var entry: Item = items[item_id]
		if entry.kind == kind:
			out.append(entry)
	return out


## The id a circuit shows when it has no choice of its own, for "breaker" or "cable".
func default_for(kind: String) -> String:
	return str(circuit_defaults.get(kind, ""))


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		problems.append("%s: file not found" % path)
		return
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		problems.append("%s: not a valid JSON object" % path)
		return
	var data: Dictionary = json.data
	var listed: Variant = data.get("items", [])
	if not (listed is Array):
		problems.append("%s: items must be an array" % path)
		return
	var raw_items: Array = listed
	for raw: Variant in raw_items:
		if not (raw is Dictionary):
			problems.append("%s: each item must be an object" % path)
			continue
		var entry: Dictionary = raw
		var built: Item = Item.new()
		built.id = str(entry.get("id", ""))
		built.kind = str(entry.get("kind", ""))
		built.title = str(entry.get("title", built.id))
		built.label = str(entry.get("label", built.title))
		built.detail = str(entry.get("detail", ""))
		if built.id.is_empty() or items.has(built.id) or not KINDS.has(built.kind):
			problems.append("%s: invalid or duplicate item '%s'" % [path, built.id])
			continue
		items[built.id] = built
		order.append(built.id)
	var defaults: Variant = data.get("circuit_defaults", {})
	if defaults is Dictionary:
		circuit_defaults = defaults
	var head: Variant = data.get("usual_head", [])
	if head is Array:
		var head_ids: Array = head
		for raw_id: Variant in head_ids:
			if items.has(str(raw_id)):
				usual_head.append(str(raw_id))
	min_rows = JsonUtil.to_int(data["ruler_min_rows"]) if JsonUtil.is_integral(data.get("ruler_min_rows")) else 8
