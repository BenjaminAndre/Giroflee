extends GutTest
@warning_ignore_start("unsafe_call_argument")

const DIR: String = "user://cli_run_script"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func after_each() -> void:
	var dir: DirAccess = DirAccess.open(DIR)
	if dir != null:
		for file: String in dir.get_files():
			dir.remove(file)


func _write(name: String, text: String) -> String:
	var path: String = "%s/%s" % [DIR, name]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


class Outcome:
	extends RefCounted
	var code: int = -1
	var output: PackedStringArray = PackedStringArray()


func _run(args: Array) -> Outcome:
	var cli: Cli = Cli.new()
	var packed: PackedStringArray = PackedStringArray()
	for arg: Variant in args:
		packed.append(str(arg))
	var outcome: Outcome = Outcome.new()
	outcome.code = cli.run(packed)
	outcome.output = cli.output
	return outcome


const ADD_SHEET: String = '{"format_version": 1, "commands": [{"type": "sheet.add", "payload": {"id": "s1", "kind": "plan", "props": {"name": "Rez"}}}]}'


func test_runs_a_script_and_prints_the_project() -> void:
	var script: String = _write("a.json", ADD_SHEET)
	var cli: Outcome = _run(["run-script", script, "--print"])
	assert_eq(cli.code, Cli.EXIT_OK, "\n".join(cli.output))
	assert_eq(cli.output[0], "ok: 1 commands applied")
	assert_string_contains("\n".join(cli.output), "\"name\": \"Rez\"")


func test_out_writes_a_project_that_can_be_extended_with_project() -> void:
	var first: String = _write("first.json", ADD_SHEET)
	var out: String = "%s/p.giroflee" % DIR
	assert_eq(_run(["run-script", first, "--out", out]).code, Cli.EXIT_OK)

	var second: String = _write("second.json", '{"format_version": 1, "commands": [{"type": "entity.add", "payload": {"sheet": "s1", "items": [{"id": "g", "type": "grey_block", "props": {"pos": [0, 0], "size": [100, 100]}}]}}]}')
	var out2: String = "%s/p2.giroflee" % DIR
	var cli: Outcome = _run(["run-script", second, "--project", out, "--out", out2])
	assert_eq(cli.code, Cli.EXIT_OK, "\n".join(cli.output))
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file(out2)
	assert_eq(loaded.error, "")
	assert_true(loaded.document.has_entity("g"))


func test_a_failing_command_stops_the_run_and_writes_nothing() -> void:
	var script: String = _write("bad.json", '{"format_version": 1, "commands": [{"type": "sheet.add", "payload": {"id": "s1", "kind": "plan", "props": {"name": "A"}}}, {"type": "entity.remove", "payload": {"sheet": "s1", "ids": ["ghost"]}}]}')
	var out: String = "%s/never.giroflee" % DIR
	var cli: Outcome = _run(["run-script", script, "--out", out])
	assert_eq(cli.code, Cli.EXIT_FAILURE)
	assert_string_contains(cli.output[0], "command 2 (entity.remove) failed")
	assert_false(FileAccess.file_exists(out), "no output file after a failure")


func test_script_errors_are_reported() -> void:
	assert_eq(_run(["run-script"]).code, Cli.EXIT_USAGE)
	assert_eq(_run(["run-script", "a.json", "b.json"]).code, Cli.EXIT_USAGE)
	assert_eq(_run(["run-script", "a.json", "--out"]).code, Cli.EXIT_USAGE)
	assert_eq(_run(["run-script", "a.json", "--bogus"]).code, Cli.EXIT_USAGE)
	assert_eq(_run(["run-script", "%s/missing.json" % DIR]).code, Cli.EXIT_FAILURE)
	var not_json: String = _write("nj.json", "{oops")
	assert_eq(_run(["run-script", not_json]).code, Cli.EXIT_FAILURE)
	var wrong_version: String = _write("v.json", '{"format_version": 7, "commands": []}')
	assert_eq(_run(["run-script", wrong_version]).code, Cli.EXIT_FAILURE)
	var no_type: String = _write("t.json", '{"format_version": 1, "commands": [{"payload": {}}]}')
	var cli: Outcome = _run(["run-script", no_type])
	assert_eq(cli.code, Cli.EXIT_FAILURE)
	assert_string_contains(cli.output[0], "command 1")


func test_unreadable_project_is_reported() -> void:
	var script: String = _write("a.json", ADD_SHEET)
	var cli: Outcome = _run(["run-script", script, "--project", "%s/nope.giroflee" % DIR])
	assert_eq(cli.code, Cli.EXIT_FAILURE)
	assert_string_contains(cli.output[0], "nope.giroflee")


func test_commands_without_ids_get_deterministic_ids() -> void:
	# two commands without ids must not collide ("script-1", "script-2")
	var script: String = _write("n.json", '{"format_version": 1, "commands": [{"type": "sheet.add", "payload": {"id": "a", "kind": "plan", "props": {"name": "A"}}}, {"type": "sheet.add", "payload": {"id": "b", "kind": "plan", "props": {"name": "B"}}}]}')
	var cli: Outcome = _run(["run-script", script])
	assert_eq(cli.code, Cli.EXIT_OK, "\n".join(cli.output))
