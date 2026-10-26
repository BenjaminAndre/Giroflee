class_name UserPrefs
extends RefCounted
## Per-user preferences that are not part of any project (SRD FR-TOOLBAR-3), kept in
## user://prefs.json. Reading never fails: a missing or damaged file gives the defaults.

static var path: String = "user://prefs.json"

const DEFAULTS: Dictionary = {"toolbar_visible": true}


static func load_prefs() -> Dictionary:
	var prefs: Dictionary = DEFAULTS.duplicate()
	if not FileAccess.file_exists(path):
		return prefs
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return prefs
	var stored: Dictionary = json.data
	for key: Variant in stored.keys():
		if DEFAULTS.has(key):
			prefs[key] = stored[key]
	return prefs


## Stores one preference. Returns "" on success or an error message.
static func set_value(key: String, value: Variant) -> String:
	var prefs: Dictionary = load_prefs()
	prefs[key] = value
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s" % path
	file.store_string(JSON.stringify(prefs, "  "))
	file.close()
	return ""
