class_name UserPrefs
extends RefCounted
## Per-user preferences that are not part of any project (SRD FR-TOOLBAR-3), kept in
## user://prefs.json. Reading never fails: a missing or damaged file gives the defaults.

static var path: String = "user://prefs.json"

## "quickbars" holds one quickbar per project (by file path): the quickbar belongs to the user and to the project.
const DEFAULTS: Dictionary = {"toolbar_visible": true, "quickbars": {}}


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


## The saved quickbar slots of a project ([] when there are none).
static func quickbar_for(project_path: String) -> Array:
	var all: Variant = load_prefs()["quickbars"]
	if all is Dictionary:
		var table: Dictionary = all
		var saved: Variant = table.get(_key(project_path), [])
		if saved is Array:
			var slots: Array = saved
			return slots
	return []


static func set_quickbar(project_path: String, slots: Array) -> String:
	var all: Variant = load_prefs()["quickbars"]
	var table: Dictionary = all if all is Dictionary else {}
	var copy: Dictionary = table.duplicate(true)
	copy[_key(project_path)] = slots
	return set_value("quickbars", copy)


## Same file, same quickbar, whatever the spelling of the path.
static func _key(project_path: String) -> String:
	return project_path.replace("\\", "/").to_lower()


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
