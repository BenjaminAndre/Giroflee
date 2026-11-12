class_name Rules
extends RefCounted
## The pack's rule values (SRD FR-RPT-6): `rules.json` when the author has made one, otherwise the
## template, where every value is `null`. A rule whose value is `null` is not applied and is reported
## as "règle non configurée", so a missing value never gives a false pass.

static var _cache: Dictionary = {}

var pack_id: String = ""
var data: Dictionary = {}
## True when the values come from `rules.json` rather than from the template.
var from_file: bool = false


static func for_pack(id: String) -> Rules:
	if not _cache.has(id):
		_cache[id] = load_dir(SymbolLibrary.PACKS_DIR, id)
	var found: Rules = _cache[id]
	return found


static func load_dir(root: String, id: String) -> Rules:
	var rules: Rules = Rules.new()
	rules.pack_id = id
	var path: String = "%s/%s/rules.json" % [root, id]
	rules.from_file = FileAccess.file_exists(path)
	if not rules.from_file:
		path = "%s/%s/rules.template.json" % [root, id]
	if FileAccess.file_exists(path):
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			rules.data = json.data
	return rules


## The section of one rule ({} when absent).
func section(rule: String) -> Dictionary:
	var value: Variant = data.get(rule, {})
	if value is Dictionary:
		var found: Dictionary = value
		return found
	return {}


## Maximum points per circuit, or -1 when not configured.
func max_points() -> int:
	var value: Variant = section("max_points_per_circuit").get("value")
	return JsonUtil.to_int(value) if JsonUtil.is_integral(value) else -1


## Allowed {"breaker_a", "section_mm2"} couples; empty when not configured.
func allowed_pairs() -> Array:
	var value: Variant = section("breaker_cable_pairs").get("allowed", [])
	if value is Array:
		var list: Array = value
		return list
	return []


## Differential rules: [{"symbol_type", "max_ma"}] that are configured (a value is set and the rule
## names a symbol type), and how many entries are not configured.
func differential_rules() -> Dictionary:
	var configured: Array = []
	var unconfigured: int = 0
	var value: Variant = section("differential_required").get("rules", [])
	var list: Array = value if value is Array else []
	for raw: Variant in list:
		var entry: Dictionary = raw
		var limit: Variant = entry.get("max_residual_current_ma")
		var when: Dictionary = entry.get("when", {})
		if not JsonUtil.is_integral(limit):
			unconfigured += 1
		elif when.has("symbol_type"):
			configured.append({"symbol_type": str(when["symbol_type"]), "max_ma": JsonUtil.to_int(limit)})
	return {"configured": configured, "unconfigured": unconfigured}


## Bathroom check: {"keywords": Array, "radius_mm": int (-1 when not configured), "message": String}.
func bathroom() -> Dictionary:
	var rule: Dictionary = section("bathroom")
	var radius: Variant = rule.get("check_radius_mm")
	var keywords: Variant = rule.get("room_keywords", [])
	return {
		"keywords": keywords if keywords is Array else [],
		"radius_mm": JsonUtil.to_int(radius) if JsonUtil.is_integral(radius) else -1,
		"message": str(rule.get("message_fr", "")),
	}


## Cartouche project fields that must not be empty (the part after "project.").
func required_cartouche_fields() -> Array[String]:
	var out: Array[String] = []
	var value: Variant = section("cartouche_required_fields").get("fields", [])
	var list: Array = value if value is Array else []
	for raw: Variant in list:
		out.append(str(raw).trim_prefix("project."))
	return out


## Head chain requirements that are switched on: kinds among "meter", "breaker", "differential".
## `configured` is false while all three are still null.
func head_requirements() -> Dictionary:
	var rule: Dictionary = section("head_chain_required")
	var kinds: Array[String] = []
	var configured: bool = false
	for pair: Array in [["require_meter", "meter"], ["require_general_breaker", "breaker"], ["require_main_differential", "differential"]]:
		var flag: Variant = rule.get(pair[0])
		if flag is bool:
			configured = true
			if flag:
				kinds.append(str(pair[1]))
	return {"kinds": kinds, "configured": configured}
