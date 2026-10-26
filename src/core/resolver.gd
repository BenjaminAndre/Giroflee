class_name Resolver
extends RefCounted
## The only writer of the Document (SRD ARCH-2, ARCH-4). Validates a command, applies it
## atomically, numbers it, and announces the resulting patch.

signal committed(patch: Patch)

var document: Document
## Number of commands committed so far (the last patch's seq).
var seq: int = 0
var _applied_ids: Dictionary = {}


func _init(p_document: Document) -> void:
	document = p_document


func submit(command: Command) -> CommandResult:
	if command.id.is_empty():
		return CommandResult.failure("command needs an id")
	if _applied_ids.has(command.id):
		return CommandResult.failure("command %s was already applied" % command.id)
	var handler: Callable = CommandRegistry.handler_for(command.type)
	if not handler.is_valid():
		return CommandResult.failure("unknown command type '%s'" % command.type)

	var built: BuildResult = handler.call(document, command.payload)
	if not built.error.is_empty():
		return CommandResult.failure("%s: %s" % [command.type, built.error])
	var error: String = PatchApplier.apply(document, built.ops, true)
	if not error.is_empty():
		return CommandResult.failure("%s: %s" % [command.type, error])

	seq += 1
	_applied_ids[command.id] = true
	var patch: Patch = Patch.new()
	patch.seq = seq
	patch.command_id = command.id
	patch.tx = command.tx
	patch.ops = built.ops
	committed.emit(patch)
	return CommandResult.success(patch)
