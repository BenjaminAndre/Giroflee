class_name ValueCommands
extends RefCounted
## Handlers for doc.set and doc.unset (project config, cartouche, board, circuits).


## payload: {section, key, value}. `config` is validated against its schema; the other
## sections accept any JSON value except null.
static func set_value(doc: Document, payload: Dictionary) -> BuildResult:
	var target: String = _section_error(payload)
	if not target.is_empty():
		return BuildResult.fail(target)
	if not payload.has("value"):
		return BuildResult.fail("doc.set needs a value")
	var section_name: String = payload["section"]
	var key: String = payload["key"]
	var value: Variant = payload["value"]
	if section_name == "config":
		if not Schema.CONFIG_SPEC.has(key):
			return BuildResult.fail("unknown config key '%s'" % key)
		var entry: Dictionary = Schema.CONFIG_SPEC[key]
		var kind: String = entry["kind"]
		var coerced: Dictionary = Schema.coerce(kind, value)
		if not JsonUtil.flag(coerced, "ok"):
			return BuildResult.fail("config.%s: %s" % [key, str(coerced["error"])])
		value = coerced["value"]
	elif value == null or not JsonUtil.is_json_value(value):
		return BuildResult.fail("value must be a JSON value (not null)")
	var section: Dictionary = doc.section(section_name)
	var before: Variant = null
	if section.has(key):
		before = JsonUtil.deep_copy(section[key])
	var ops: Array[Dictionary] = []
	if before == null or before != value:
		ops.append(Patch.value_op(section_name, key, before, JsonUtil.deep_copy(value)))
	return BuildResult.success(ops)


## payload: {section, key}. Not allowed on `config` (set the value back instead).
static func unset(doc: Document, payload: Dictionary) -> BuildResult:
	var problem: String = _section_error(payload)
	if not problem.is_empty():
		return BuildResult.fail(problem)
	var section_name: String = payload["section"]
	var key: String = payload["key"]
	if section_name == "config":
		return BuildResult.fail("config keys cannot be unset")
	var section: Dictionary = doc.section(section_name)
	if not section.has(key):
		return BuildResult.fail("%s.%s does not exist" % [section_name, key])
	var ops: Array[Dictionary] = [Patch.value_op(section_name, key, JsonUtil.deep_copy(section[key]), null)]
	return BuildResult.success(ops)


static func _section_error(payload: Dictionary) -> String:
	if not JsonUtil.has_string(payload, "section") or not JsonUtil.has_string(payload, "key"):
		return "payload needs section and key"
	var section_name: String = payload["section"]
	if not Document.VALUE_SECTIONS.has(section_name):
		return "unknown section '%s'" % section_name
	var key: String = payload["key"]
	if key.is_empty():
		return "key must not be empty"
	return ""
