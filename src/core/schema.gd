class_name Schema
extends RefCounted
## Property schemas for entities, sheets and project config, plus normalisation.
##
## A spec maps a property name to {"kind": String, "default": Variant, "required": bool}.
## Kinds: int, float, string, bool, vec2i, points, string_array, "enum:a|b|c".
## Coordinates are integer millimetres (SRD ARCH-C); values read from JSON are normalised
## (an integral float becomes an int where an int is expected).

const ENTITY_TYPES: PackedStringArray = [
	"wall", "opening", "stair", "grey_block", "text", "symbol",
]

const ENTITY_SPECS: Dictionary = {
	"wall": {
		"points": {"kind": "points", "required": true},
		"weight_mm": {"kind": "float", "default": 1.4},
	},
	"opening": {
		"kind": {"kind": "enum:door|window", "required": true},
		"pos": {"kind": "vec2i", "required": true},
		"width_mm": {"kind": "int", "required": true},
		"rotation": {"kind": "float", "default": 0.0},
		"flip_h": {"kind": "bool", "default": false},
		"flip_v": {"kind": "bool", "default": false},
		"host_wall": {"kind": "string", "default": ""},
		"host_offset_mm": {"kind": "int", "default": 0},
	},
	"stair": {
		"pos": {"kind": "vec2i", "required": true},
		"width_mm": {"kind": "int", "required": true},
		"steps": {"kind": "int", "required": true},
		"tread_mm": {"kind": "int", "required": true},
		"rotation": {"kind": "float", "default": 0.0},
		"flip_h": {"kind": "bool", "default": false},
		"flip_v": {"kind": "bool", "default": false},
	},
	"grey_block": {
		"pos": {"kind": "vec2i", "required": true},
		"size": {"kind": "vec2i", "required": true},
		"rotation": {"kind": "float", "default": 0.0},
	},
	"text": {
		"pos": {"kind": "vec2i", "required": true},
		"text": {"kind": "string", "required": true},
		"role": {"kind": "enum:free|room|floor|symbol|other", "default": "free"},
		"rotation": {"kind": "float", "default": 0.0},
		"font": {"kind": "string", "default": ""},
		"size_pt": {"kind": "float", "default": 0.0},
	},
	"symbol": {
		"symbol_type": {"kind": "string", "required": true},
		"pos": {"kind": "vec2i", "required": true},
		"circuit": {"kind": "string", "default": ""},
		"index": {"kind": "int", "default": 0},
		"count": {"kind": "int", "default": 1},
		"rotation": {"kind": "float", "default": 0.0},
		"flip_h": {"kind": "bool", "default": false},
		"flip_v": {"kind": "bool", "default": false},
		"label_pinned": {"kind": "bool", "default": false},
		"label_offset": {"kind": "vec2i", "default": [0, 0]},
		"count_offset": {"kind": "vec2i", "default": [0, 0]},
		"height_mm": {"kind": "int", "default": -1},
		"anchor_parent": {"kind": "string", "default": ""},
		"anchor_offset": {"kind": "vec2i", "default": [0, 0]},
	},
}

const SHEET_KINDS: PackedStringArray = ["plan", "unifilaire"]

const SHEET_SPEC: Dictionary = {
	"name": {"kind": "string", "required": true},
	"paper_w_mm": {"kind": "int", "default": 420},
	"paper_h_mm": {"kind": "int", "default": 297},
	"scale_den": {"kind": "int", "default": 50},
	"frame_cols": {"kind": "int", "default": 17},
	"frame_rows": {"kind": "int", "default": 8},
	"grid_step_mm": {"kind": "int", "default": 100},
	"hints": {"kind": "bool", "default": true},
	"title_pos_mm": {"kind": "vec2i", "default": [366, 34]},
	"ghost_on": {"kind": "bool", "default": false},
	"ghost_sheets": {"kind": "string_array", "default": []},
}

const CONFIG_SPEC: Dictionary = {
	"font_family": {"kind": "string", "default": "Atkinson Hyperlegible"},
	"font_size_pt": {"kind": "float", "default": 10.0},
	"wall_weight_mm": {"kind": "float", "default": 1.4},
	"provisoire_mark": {"kind": "bool", "default": true},
}

## Document sections without a schema yet (they get one in later milestones).
const FREE_SECTIONS: PackedStringArray = ["cartouche", "board", "circuits"]


static func has_entity_type(type: String) -> bool:
	return ENTITY_SPECS.has(type)


static func entity_spec(type: String) -> Dictionary:
	var spec: Dictionary = ENTITY_SPECS[type]
	return spec


## Validates and normalises a value of the given kind.
## Returns {"ok": bool, "value": Variant, "error": String}.
static func coerce(kind: String, value: Variant) -> Dictionary:
	match kind:
		"int":
			if JsonUtil.is_integral(value):
				return _ok(JsonUtil.to_int(value))
			return _bad("expected an integer")
		"float":
			if JsonUtil.is_number(value):
				return _ok(JsonUtil.to_float(value))
			return _bad("expected a number")
		"string":
			if value is String:
				return _ok(value)
			return _bad("expected a string")
		"bool":
			if value is bool:
				return _ok(value)
			return _bad("expected a boolean")
		"vec2i":
			return _coerce_vec2i(value)
		"points":
			if not (value is Array):
				return _bad("expected an array of points")
			var points: Array = []
			var raw: Array = value
			for item: Variant in raw:
				var point: Dictionary = _coerce_vec2i(item)
				if not JsonUtil.flag(point, "ok"):
					return point
				points.append(point["value"])
			return _ok(points)
		"string_array":
			if not (value is Array):
				return _bad("expected an array of strings")
			var strings: Array = []
			var raw_strings: Array = value
			for item: Variant in raw_strings:
				if not (item is String):
					return _bad("expected an array of strings")
				strings.append(item)
			return _ok(strings)
	if kind.begins_with("enum:"):
		var allowed: PackedStringArray = kind.substr(5).split("|")
		if value is String:
			var text: String = value
			if allowed.has(text):
				return _ok(text)
		return _bad("expected one of %s" % ", ".join(allowed))
	return _bad("unknown kind '%s'" % kind)


## Validates `props` against `spec` and returns {"ok", "props", "error"}.
## With `fill_defaults` (creation) missing properties receive their default and required ones
## must be present; without it (partial update) only the given keys are checked.
static func normalize(spec: Dictionary, props: Dictionary, fill_defaults: bool) -> Dictionary:
	var out: Dictionary = {}
	for raw_key: Variant in props.keys():
		if not (raw_key is String):
			return _failure("property names must be strings")
		var key: String = raw_key
		if not spec.has(key):
			return _failure("unknown property '%s'" % key)
		var entry: Dictionary = spec[key]
		var kind: String = entry["kind"]
		var result: Dictionary = coerce(kind, props[key])
		if not JsonUtil.flag(result, "ok"):
			return _failure("property '%s': %s" % [key, str(result["error"])])
		out[key] = result["value"]
	if fill_defaults:
		for spec_key: String in spec.keys():
			if out.has(spec_key):
				continue
			var spec_entry: Dictionary = spec[spec_key]
			if spec_entry.has("default"):
				out[spec_key] = JsonUtil.deep_copy(spec_entry["default"])
			elif JsonUtil.flag(spec_entry, "required"):
				return _failure("missing required property '%s'" % spec_key)
	return {"ok": true, "props": out, "error": ""}


## Cross-property rules for a complete entity. Returns "" when valid, else a message.
static func check_entity(type: String, props: Dictionary) -> String:
	match type:
		"wall":
			var points: Array = props["points"]
			if points.size() < 2:
				return "a wall needs at least 2 points"
			var weight: float = props["weight_mm"]
			if weight <= 0.0:
				return "weight_mm must be positive"
		"opening":
			var width: int = props["width_mm"]
			if width <= 0:
				return "width_mm must be positive"
		"stair":
			var stair_width: int = props["width_mm"]
			var steps: int = props["steps"]
			var tread: int = props["tread_mm"]
			if stair_width <= 0 or steps <= 0 or tread <= 0:
				return "width_mm, steps and tread_mm must be positive"
		"grey_block":
			var size: Array = props["size"]
			var w: int = size[0]
			var h: int = size[1]
			if w <= 0 or h <= 0:
				return "size must be positive"
		"symbol":
			var symbol_type: String = props["symbol_type"]
			if symbol_type.is_empty():
				return "symbol_type must not be empty"
			var count: int = props["count"]
			var index: int = props["index"]
			if count < 1:
				return "count must be at least 1"
			if index < 0:
				return "index must not be negative"
			var circuit: String = props["circuit"]
			if circuit.length() > 1:
				return "circuit must be empty or a single letter"
			if circuit.length() == 1 and (circuit < "A" or circuit > "Z"):
				return "circuit must be a letter A-Z"
	return ""


## Cross-property rules for a complete sheet props dictionary.
static func check_sheet(props: Dictionary) -> String:
	for key: String in ["paper_w_mm", "paper_h_mm", "scale_den", "grid_step_mm"]:
		var value: int = props[key]
		if value <= 0:
			return "%s must be positive" % key
	for key: String in ["frame_cols", "frame_rows"]:
		var count: int = props[key]
		if count < 0:
			return "%s must not be negative" % key
	return ""


static func default_config() -> Dictionary:
	var result: Dictionary = normalize(CONFIG_SPEC, {}, true)
	var props: Dictionary = result["props"]
	return props


static func _coerce_vec2i(value: Variant) -> Dictionary:
	if not (value is Array):
		return _bad("expected [x, y]")
	var arr: Array = value
	if arr.size() != 2 or not JsonUtil.is_integral(arr[0]) or not JsonUtil.is_integral(arr[1]):
		return _bad("expected [x, y] with integer millimetres")
	return _ok([JsonUtil.to_int(arr[0]), JsonUtil.to_int(arr[1])])


static func _ok(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


static func _bad(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "props": {}, "error": message}
