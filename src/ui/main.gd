extends Node
## Application entry point. With `-- giroflee-cli ...` it runs the headless CLI and exits;
## otherwise it opens the editor window.
##
## GUI arguments (after `--`):
##   --open <file>   open a project file
##   --slot=<n>      autosave slot of this window (default 0)
##   --new           start with an empty project instead of recovering the slot's autosave


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == Cli.COMMAND_NAME:
		var cli: Cli = Cli.new()
		var code: int = cli.run(args.slice(1))
		for line: String in cli.output:
			print(line)
		get_tree().quit(code)
		return
	_start_gui(args)


func _start_gui(args: PackedStringArray) -> void:
	var slot: int = 0
	var open_path: String = ""
	var fresh: bool = false
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg.begins_with("--slot="):
			slot = arg.substr(7).to_int()
		elif arg == "--open" and i + 1 < args.size():
			open_path = args[i + 1]
			i += 1
		elif arg == "--new":
			fresh = true
		i += 1

	var window: EditorWindow = EditorWindow.new()
	window.slot = slot
	add_child(window)

	var document: Document = null
	var path: String = ""
	if not open_path.is_empty():
		var loaded: DocumentIO.LoadResult = DocumentIO.load_file(open_path)
		if loaded.document != null:
			document = loaded.document
			path = open_path
		else:
			push_warning("cannot open %s: %s" % [open_path, loaded.error])
	elif fresh:
		ProjectFiles.clear_autosave(slot)
	else:
		var recovered: Dictionary = ProjectFiles.read_autosave(slot)
		var recovered_doc: Variant = recovered["document"]
		if recovered_doc is Document:
			document = recovered_doc
			path = str(recovered["project_path"])
	window.open_document(document, path)
	DisplayServer.window_set_title("%s %s" % [AppInfo.APP_NAME, AppInfo.version()])
