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
