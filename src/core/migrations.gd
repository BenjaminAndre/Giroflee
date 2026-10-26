class_name Migrations
extends RefCounted
## Upgrades a raw project dictionary from an older format_version to the current one
## (SRD FR-FILE-2). A file from an older version must open; a file from a newer version
## is refused with a clear message, never silently truncated.
##
## The registry maps `from_version` (int) to a Callable(raw: Dictionary) -> Dictionary that
## returns the data upgraded by exactly one version. The runner sets `format_version`.


## Migrations shipped with the app.
static func default_registry() -> Dictionary:
	return {1: _v1_to_v2}


## Format 2 moves the border frame, the étage-title position, the ghost-view switch and the A4/A3
## hints from each sheet to the project config (SRD FR-PROJ-1). The values of the first sheet
## are kept; a file without sheets gets the defaults.
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var config: Dictionary = out.get("config", {})
	var defaults: Dictionary = Schema.default_config()
	var sheets: Array = out.get("sheets", [])
	var source: Dictionary = {}
	if not sheets.is_empty():
		var first: Dictionary = sheets[0]
		source = first.get("props", {})
	for key: String in Schema.MOVED_TO_CONFIG:
		if source.has(key):
			config[key] = source[key]
		elif not config.has(key):
			config[key] = defaults[key]
	for item: Variant in sheets:
		var sheet: Dictionary = item
		var props: Dictionary = sheet.get("props", {})
		for key: String in Schema.MOVED_TO_CONFIG:
			props.erase(key)
	out["config"] = config
	return out


## Returns {"ok": bool, "data": Dictionary, "error": String}.
static func migrate(raw: Dictionary, target: int, registry: Dictionary) -> Dictionary:
	if not raw.has("format_version") or not JsonUtil.is_integral(raw["format_version"]):
		return _fail("missing or invalid format_version")
	var version: int = JsonUtil.to_int(raw["format_version"])
	if version > target:
		return _fail("file was written by a newer version of Giroflée (format %d, this one reads up to %d)" % [version, target])
	if version < 1:
		return _fail("invalid format_version %d" % version)
	var data: Dictionary = raw.duplicate(true)
	while version < target:
		if not registry.has(version):
			return _fail("no migration from format %d" % version)
		var step: Callable = registry[version]
		var upgraded: Dictionary = step.call(data)
		version += 1
		upgraded["format_version"] = version
		data = upgraded
	return {"ok": true, "data": data, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
