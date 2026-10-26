extends GutTest
@warning_ignore_start("unsafe_call_argument")


func test_int_accepts_integral_floats_only() -> void:
	assert_eq(Schema.coerce("int", 100.0)["value"], 100)
	assert_true(Schema.coerce("int", 100.0)["value"] is int, "normalised to int")
	assert_false(Schema.coerce("int", 1.5)["ok"])
	assert_false(Schema.coerce("int", "12")["ok"])
	assert_false(Schema.coerce("int", true)["ok"])


func test_float_accepts_ints_and_converts() -> void:
	var result: Dictionary = Schema.coerce("float", 3)
	assert_true(result["ok"])
	assert_true(result["value"] is float)
	assert_false(Schema.coerce("float", "3")["ok"])
	assert_false(Schema.coerce("float", INF)["ok"], "infinity is not a valid number")


func test_vec2i_is_normalised_and_strict() -> void:
	assert_eq(Schema.coerce("vec2i", [10.0, 20])["value"], [10, 20])
	assert_false(Schema.coerce("vec2i", [1, 2, 3])["ok"])
	assert_false(Schema.coerce("vec2i", [1.5, 2])["ok"])
	assert_false(Schema.coerce("vec2i", "1,2")["ok"])


func test_points_and_string_array() -> void:
	assert_eq(Schema.coerce("points", [[0, 0], [100.0, 0]])["value"], [[0, 0], [100, 0]])
	assert_false(Schema.coerce("points", [[0, 0], [1]])["ok"])
	assert_true(Schema.coerce("string_array", ["a", "b"])["ok"])
	assert_false(Schema.coerce("string_array", ["a", 1])["ok"])


func test_enum() -> void:
	assert_true(Schema.coerce("enum:door|window", "door")["ok"])
	assert_false(Schema.coerce("enum:door|window", "gate")["ok"])
	assert_false(Schema.coerce("enum:door|window", 3)["ok"])


func test_unknown_kind_is_rejected() -> void:
	assert_false(Schema.coerce("quaternion", 1)["ok"])


func test_normalize_fills_defaults_and_requires_required() -> void:
	var spec: Dictionary = Schema.entity_spec("wall")
	var ok: Dictionary = Schema.normalize(spec, {"points": [[0, 0], [10, 0]]}, true)
	assert_true(ok["ok"])
	var props: Dictionary = ok["props"]
	assert_eq(props["weight_mm"], 1.4, "default filled")
	var missing: Dictionary = Schema.normalize(spec, {}, true)
	assert_false(missing["ok"])
	assert_string_contains(missing["error"], "points")


func test_normalize_partial_update_does_not_fill_or_require() -> void:
	var spec: Dictionary = Schema.entity_spec("wall")
	var result: Dictionary = Schema.normalize(spec, {"weight_mm": 2}, false)
	assert_true(result["ok"])
	var props: Dictionary = result["props"]
	assert_eq(props.size(), 1)
	assert_eq(props["weight_mm"], 2.0)


func test_normalize_rejects_unknown_property() -> void:
	var result: Dictionary = Schema.normalize(Schema.entity_spec("wall"), {"colour": "red"}, false)
	assert_false(result["ok"])
	assert_string_contains(result["error"], "colour")


func test_defaults_are_not_shared_between_results() -> void:
	var spec: Dictionary = Schema.entity_spec("symbol")
	var a: Dictionary = Schema.normalize(spec, {"symbol_type": "lamp", "pos": [0, 0]}, true)
	var b: Dictionary = Schema.normalize(spec, {"symbol_type": "lamp", "pos": [0, 0]}, true)
	var props_a: Dictionary = a["props"]
	var props_b: Dictionary = b["props"]
	var offset_a: Array = props_a["label_offset"]
	offset_a[0] = 99
	var offset_b: Array = props_b["label_offset"]
	assert_eq(offset_b[0], 0, "mutating one result must not leak into another")


func test_check_entity_rules() -> void:
	var wall: Dictionary = Schema.normalize(Schema.entity_spec("wall"), {"points": [[0, 0]]}, true)["props"]
	assert_ne(Schema.check_entity("wall", wall), "", "a wall needs 2 points")

	var base: Dictionary = {"symbol_type": "lamp", "pos": [0, 0]}
	var symbol: Dictionary = Schema.normalize(Schema.entity_spec("symbol"), base, true)["props"]
	assert_eq(Schema.check_entity("symbol", symbol), "")
	symbol["circuit"] = "a"
	assert_ne(Schema.check_entity("symbol", symbol), "", "circuit must be an upper-case letter")
	symbol["circuit"] = "AB"
	assert_ne(Schema.check_entity("symbol", symbol), "")
	symbol["circuit"] = "B"
	symbol["count"] = 0
	assert_ne(Schema.check_entity("symbol", symbol), "", "count must be >= 1")

	var block: Dictionary = Schema.normalize(Schema.entity_spec("grey_block"), {"pos": [0, 0], "size": [0, 10]}, true)["props"]
	assert_ne(Schema.check_entity("grey_block", block), "")


func test_every_entity_type_has_a_spec_and_creatable_defaults() -> void:
	for type: String in Schema.ENTITY_TYPES:
		assert_true(Schema.has_entity_type(type), type)
		var spec: Dictionary = Schema.entity_spec(type)
		for key: String in spec.keys():
			var entry: Dictionary = spec[key]
			assert_true(entry.has("default") or entry.get("required", false), "%s.%s needs a default or required" % [type, key])


func test_default_config_matches_spec() -> void:
	var config: Dictionary = Schema.default_config()
	assert_eq(config.size(), Schema.CONFIG_SPEC.size())
	assert_eq(config["font_family"], "Atkinson Hyperlegible")
