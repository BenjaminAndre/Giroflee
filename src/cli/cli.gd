class_name Cli
extends RefCounted
## Headless command-line interface (SRD ARCH-10).
##
## Usage:  godot --headless --path . -- giroflee-cli <subcommand> [args]
##
## `run()` returns the process exit code and collects the text to print in `output`,
## so that tests can drive it without a process.

const COMMAND_NAME: String = "giroflee-cli"

const EXIT_OK: int = 0
const EXIT_FAILURE: int = 1
const EXIT_USAGE: int = 2

## Subcommands announced by the SRD and not implemented yet (milestone in brackets).
const PLANNED: Dictionary = {
	"run-script": "M1",
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
		_:
			if PLANNED.has(args[0]):
				output.append("%s: not implemented yet (planned for %s)" % [args[0], PLANNED[args[0]]])
				return EXIT_USAGE
			output.append("unknown subcommand: %s" % args[0])
			_usage()
			return EXIT_USAGE


func _usage() -> void:
	output.append("usage: %s <subcommand> [args]" % COMMAND_NAME)
	output.append("subcommands: help, version, %s" % ", ".join(PackedStringArray(PLANNED.keys())))
