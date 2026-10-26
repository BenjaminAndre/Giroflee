extends GutTest
@warning_ignore_start("unsafe_call_argument")


func _bump(name: String) -> Callable:
	return func(data: Dictionary) -> Dictionary:
		var copy: Dictionary = data.duplicate(true)
		var trail: Array = copy.get("trail", [])
		trail.append(name)
		copy["trail"] = trail
		return copy


func test_chain_runs_each_step_in_order() -> void:
	var registry: Dictionary = {1: _bump("1to2"), 2: _bump("2to3")}
	var result: Dictionary = Migrations.migrate({"format_version": 1}, 3, registry)
	assert_true(result["ok"], str(result["error"]))
	var data: Dictionary = result["data"]
	assert_eq(data["format_version"], 3)
	assert_eq(data["trail"], ["1to2", "2to3"])


func test_current_version_needs_no_migration() -> void:
	var result: Dictionary = Migrations.migrate({"format_version": 1, "x": 1}, 1, {})
	assert_true(result["ok"])
	var data: Dictionary = result["data"]
	assert_eq(data["x"], 1)


func test_json_style_float_version_is_accepted() -> void:
	var result: Dictionary = Migrations.migrate({"format_version": 2.0}, 2, {})
	assert_true(result["ok"])


func test_missing_step_is_an_error() -> void:
	var result: Dictionary = Migrations.migrate({"format_version": 1}, 3, {1: _bump("1to2")})
	assert_false(result["ok"])
	assert_string_contains(result["error"], "no migration from format 2")


func test_newer_file_is_refused_not_truncated() -> void:
	var result: Dictionary = Migrations.migrate({"format_version": 9}, 1, {})
	assert_false(result["ok"])
	assert_string_contains(result["error"], "newer version")


func test_missing_or_invalid_version_is_an_error() -> void:
	assert_false(Migrations.migrate({}, 1, {})["ok"])
	assert_false(Migrations.migrate({"format_version": "1"}, 1, {})["ok"])
	assert_false(Migrations.migrate({"format_version": 1.5}, 1, {})["ok"])
	assert_false(Migrations.migrate({"format_version": 0}, 1, {})["ok"])


func test_input_is_not_mutated() -> void:
	var raw: Dictionary = {"format_version": 1}
	Migrations.migrate(raw, 2, {1: _bump("1to2")})
	assert_false(raw.has("trail"))
	assert_eq(raw["format_version"], 1)
