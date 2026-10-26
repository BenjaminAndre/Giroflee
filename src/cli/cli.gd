class_name Cli
extends RefCounted
## Headless command-line interface (SRD ARCH-10).
##
## Usage:  godot --headless --path . -- giroflee-cli <subcommand> [args]
##
## `run()` returns the process exit code and collects the text to print in `output`,
## so that tests can drive it without a process.
##
## run-script <script.json> [--project <file>] [--out <file>] [--print]
##   Applies the commands of a script to a project (a new empty one unless --project is
##   given), through the same resolver as the GUI. Script format:
##     { "format_version": 1, "commands": [ { "type": "...", "payload": {...}, "id"?: "..." } ] }
##   Commands without an id get "script-<n>". Entity and sheet ids must be given in payloads
##   (that is what keeps scripts deterministic). With --out the result is saved; with --print
##   the resulting project JSON is printed.

const COMMAND_NAME: String = "giroflee-cli"
const SCRIPT_FORMAT_VERSION: int = 1

const EXIT_OK: int = 0
const EXIT_FAILURE: int = 1
const EXIT_USAGE: int = 2

## Subcommands announced by the SRD and not implemented yet (milestone in brackets).
const PLANNED: Dictionary = {
	"export-svg": "M6",
	"derive-unifilaire": "M4",
	"validate": "M5",
}

var output: PackedStringArray = PackedStringArray()


## Runs one subcommand. `args[0]` is the subcommand name.
func run(args: PackedStringArray) -> int:
	output = PackedStringArray()
	if args.is_empty():
		_usage()
		return EXIT_USAGE
	match args[0]:
		"help", "--help", "-h":
			_usage()
			return EXIT_OK
		"version", "--version":
			output.append("%s %s (Godot %s)" % [AppInfo.APP_NAME, AppInfo.version(), AppInfo.engine_version()])
			return EXIT_OK
		"run-script":
			return _run_script(args.slice(1))
		_:
			if PLANNED.has(args[0]):
				output.append("%s: not implemented yet (planned for %s)" % [args[0], PLANNED[args[0]]])
				return EXIT_USAGE
			output.append("unknown subcommand: %s" % args[0])
			_usage()
			return EXIT_USAGE


func _usage() -> void:
	output.append("usage: %s <subcommand> [args]" % COMMAND_NAME)
	var names: PackedStringArray = PackedStringArray(["help", "version", "run-script"])
	names.append_array(PackedStringArray(PLANNED.keys()))
	output.append("subcommands: %s" % ", ".join(names))
	output.append("run-script <script.json> [--project <file>] [--out <file>] [--print]")


func _run_script(args: PackedStringArray) -> int:
	var script_path: String = ""
	var project_path: String = ""
	var out_path: String = ""
	var print_project: bool = false
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--project" or arg == "--out":
			if i + 1 >= args.size():
				output.append("%s needs a value" % arg)
				return EXIT_USAGE
			if arg == "--project":
				project_path = args[i + 1]
			else:
				out_path = args[i + 1]
			i += 2
			continue
		if arg == "--print":
			print_project = true
		elif arg.begins_with("--") or not script_path.is_empty():
			output.append("unexpected argument: %s" % arg)
			return EXIT_USAGE
		else:
			script_path = arg
		i += 1
	if script_path.is_empty():
		output.append("run-script needs a script file")
		return EXIT_USAGE

	var script: Dictionary = _read_json(script_path)
	if script.has("error"):
		output.append(str(script["error"]))
		return EXIT_FAILURE
	var commands: Array = []
	var shape_error: String = _check_script(script)
	if not shape_error.is_empty():
		output.append("%s: %s" % [script_path, shape_error])
		return EXIT_FAILURE
	commands = script["commands"]

	var doc: Document = Document.new_project()
	if not project_path.is_empty():
		var loaded: DocumentIO.LoadResult = DocumentIO.load_file(project_path)
		if loaded.document == null:
			output.append("%s: %s" % [project_path, loaded.error])
			return EXIT_FAILURE
		doc = loaded.document

	var channel: InProcessChannel = InProcessChannel.new(doc)
	for index: int in commands.size():
		var entry: Dictionary = commands[index]
		var command: Command = Command.from_dict(entry, "script-%d" % (index + 1))
		var result: CommandResult = channel.submit(command)
		if not result.ok:
			output.append("command %d (%s) failed: %s" % [index + 1, command.type, result.error])
			return EXIT_FAILURE

	if not out_path.is_empty():
		var save_error: String = DocumentIO.save_file(doc, out_path)
		if not save_error.is_empty():
			output.append(save_error)
			return EXIT_FAILURE
	output.append("ok: %d commands applied" % commands.size())
	if print_project:
		output.append(DocumentIO.to_json(doc).trim_suffix("\n"))
	return EXIT_OK


## Returns the parsed JSON object, or {"error": message}.
func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot read %s" % path}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": "%s: invalid JSON (line %d): %s" % [path, json.get_error_line(), json.get_error_message()]}
	var data: Variant = json.data
	if not (data is Dictionary):
		return {"error": "%s: a JSON object is expected" % path}
	var dict: Dictionary = data
	return dict


## Returns "" when the script has the expected shape.
func _check_script(script: Dictionary) -> String:
	if not JsonUtil.is_integral(script.get("format_version")) or JsonUtil.to_int(script["format_version"]) != SCRIPT_FORMAT_VERSION:
		return "unsupported or missing format_version (expected %d)" % SCRIPT_FORMAT_VERSION
	if not JsonUtil.has_array(script, "commands"):
		return "commands must be an array"
	var commands: Array = script["commands"]
	for index: int in commands.size():
		var item: Variant = commands[index]
		if not (item is Dictionary):
			return "command %d is not an object" % (index + 1)
		var entry: Dictionary = item
		var problem: String = Command.validate_dict(entry)
		if not problem.is_empty():
			return "command %d: %s" % [index + 1, problem]
	return ""
