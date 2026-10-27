extends GutTest


func test_no_arguments_is_a_usage_error() -> void:
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray()), Cli.EXIT_USAGE)
	assert_true(cli.output.size() > 0, "usage is printed")


func test_version_prints_app_and_engine_versions() -> void:
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray(["version"])), Cli.EXIT_OK)
	assert_eq(cli.output.size(), 1)
	assert_string_contains(cli.output[0], AppInfo.version())
	assert_string_contains(cli.output[0], AppInfo.engine_version())


func test_help_lists_every_planned_subcommand() -> void:
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray(["help"])), Cli.EXIT_OK)
	var text: String = "\n".join(cli.output)
	assert_string_contains(text, "run-script")
	for name: String in Cli.PLANNED.keys():
		assert_string_contains(text, name)


func test_unknown_subcommand_is_a_usage_error() -> void:
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray(["frobnicate"])), Cli.EXIT_USAGE)
	assert_string_contains(cli.output[0], "frobnicate")


func test_planned_subcommands_fail_loudly_until_implemented() -> void:
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray(["export-svg"])), Cli.EXIT_USAGE)
	assert_string_contains(cli.output[0], "not implemented")


func test_output_is_reset_between_runs() -> void:
	var cli: Cli = Cli.new()
	cli.run(PackedStringArray(["version"]))
	cli.run(PackedStringArray(["version"]))
	assert_eq(cli.output.size(), 1)


func test_derive_unifilaire_prints_the_derived_model_as_json() -> void:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "p1", "Rez")
	TestKit.add_symbol(s, "p1", "a", [1000, 1000], "A", 1)
	var path: String = "user://cli_derive_test.giroflee"
	assert_eq(DocumentIO.save_file(s.document(), path), "")
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray(["derive-unifilaire", path])), Cli.EXIT_OK, "\n".join(cli.output))
	var json: JSON = JSON.new()
	assert_eq(json.parse("\n".join(cli.output)), OK)
	var data: Dictionary = json.data
	var columns: Array = data["columns"]
	assert_eq(columns.size(), 1)
	var rows: int = data["rows"]
	assert_eq(rows, 8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_derive_unifilaire_reports_bad_usage_and_unreadable_files() -> void:
	var cli: Cli = Cli.new()
	assert_eq(cli.run(PackedStringArray(["derive-unifilaire"])), Cli.EXIT_USAGE)
	assert_eq(cli.run(PackedStringArray(["derive-unifilaire", "user://nowhere.giroflee"])), Cli.EXIT_FAILURE)
