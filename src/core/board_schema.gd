class_name BoardSchema
extends RefCounted
## What `board`, `circuits` and `cartouche` may hold (SRD FR-UNI-3). `doc.set` calls this, so a bad
## value is refused instead of being saved and breaking the unifilaire later.

const CIRCUIT_KEYS: PackedStringArray = ["title", "breaker", "cable"]
const BUS_DEVICE_KINDS: PackedStringArray = ["differential", "breaker"]


## "" when `value` is fine for `section`.`key`, otherwise a message.
static func check(catalog: Catalog, section: String, key: String, value: Variant) -> String:
	match section:
		"board":
			return _check_board(catalog, key, value)
		"circuits":
			return _check_circuit(catalog, key, value)
		"cartouche":
			if not (value is String):
				return "cartouche.%s must be text" % key
	return ""


static func _check_board(catalog: Catalog, key: String, value: Variant) -> String:
	if key != "head" and key != "bus":
		return "unknown board key '%s' (head or bus)" % key
	if not (value is Array):
		return "board.%s must be a list" % key
	var list: Array = value
	var ids: Dictionary = {}
	var letters: Dictionary = {}
	for raw: Variant in list:
		if not (raw is Dictionary):
			return "board.%s items must be objects" % key
		var entry: Dictionary = raw
		var type: String = str(entry.get("type", "device"))
		if key == "bus" and type == "circuit":
			var letter: String = str(entry.get("letter", ""))
			if not CircuitPalette.is_letter(letter):
				return "bus circuit '%s' is not a letter A to Z" % letter
			if letters.has(letter):
				return "circuit %s appears twice in the bus" % letter
			letters[letter] = true
			continue
		if type != "device":
			return "board.%s item type '%s' is not allowed" % [key, type]
		var item_id: String = str(entry.get("id", ""))
		if item_id.is_empty() or ids.has(item_id):
			return "board.%s needs a unique id on every device" % key
		ids[item_id] = true
		var item: Catalog.Item = catalog.item(str(entry.get("catalog", "")))
		if item == null:
			return "board.%s: unknown catalogue item '%s'" % [key, str(entry.get("catalog", ""))]
		if key == "bus" and not BUS_DEVICE_KINDS.has(item.kind):
			return "a %s cannot sit on the bus" % item.kind
	return ""


static func _check_circuit(catalog: Catalog, key: String, value: Variant) -> String:
	if not CircuitPalette.is_letter(key):
		return "circuits keys are letters A to Z, not '%s'" % key
	if not (value is Dictionary):
		return "circuits.%s must be an object" % key
	var data: Dictionary = value
	for raw_key: Variant in data.keys():
		var field: String = str(raw_key)
		if not CIRCUIT_KEYS.has(field):
			return "circuits.%s: unknown field '%s'" % [key, field]
		if not (data[raw_key] is String):
			return "circuits.%s.%s must be text" % [key, field]
	for kind: String in ["breaker", "cable"]:
		if data.has(kind):
			var item: Catalog.Item = catalog.item(str(data[kind]))
			if item == null or item.kind != kind:
				return "circuits.%s.%s: '%s' is not a catalogue %s" % [key, kind, str(data[kind]), kind]
	return ""
