extends Node
## Application entry point. With `-- giroflee-cli ...` it runs the headless CLI and exits;
## otherwise it starts the GUI (placeholder until milestone M2).


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == Cli.COMMAND_NAME:
		var cli: Cli = Cli.new()
		var code: int = cli.run(args.slice(1))
		for line: String in cli.output:
			print(line)
		get_tree().quit(code)
		return

	DisplayServer.window_set_title("%s %s" % [AppInfo.APP_NAME, AppInfo.version()])
	var label: Label = Label.new()
	label.text = "%s %s" % [AppInfo.APP_NAME, AppInfo.version()]
	add_child(label)
