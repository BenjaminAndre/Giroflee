class_name Session
extends RefCounted
## One user's client state: a channel to the resolver, an id generator and the undo history.
## The UI talks to a Session, never to the Document directly (SRD ARCH-2).

## Emitted after a transaction, an undo or a redo was committed.
signal changed

var channel: CommandChannel
var history: History = History.new()
var ids: IdGenerator
var author: String
## Message of the last failed operation ("" if none).
var last_error: String = ""


func _init(p_channel: CommandChannel, p_ids: IdGenerator = null, p_author: String = "local") -> void:
	channel = p_channel
	ids = p_ids if p_ids != null else IdGenerator.new()
	author = p_author


func document() -> Document:
	return channel.get_document()


## Creates a command with a fresh id. `tx` is assigned by `run()`.
func command(type: String, payload: Dictionary) -> Command:
	return Command.make(type, payload, ids.next_uuid(), "", author)


## Runs commands as ONE undo step. If one fails, the earlier ones are rolled back and
## nothing is recorded. Returns the failing result, or the last result on success.
func run(commands: Array[Command]) -> CommandResult:
	if commands.is_empty():
		return _fail("nothing to run")
	var tx: String = ids.next_uuid()
	var applied: Array[Dictionary] = []
	var result: CommandResult = null
	for cmd: Command in commands:
		cmd.tx = tx
		result = channel.submit(cmd)
		if not result.ok:
			_rollback(applied, tx)
			last_error = result.error
			return result
		applied.append_array(result.patch.ops)
	history.record(tx, applied)
	last_error = ""
	changed.emit()
	return result


## Convenience for a single command.
func run_one(type: String, payload: Dictionary) -> CommandResult:
	var commands: Array[Command] = [command(type, payload)]
	return run(commands)


func can_undo() -> bool:
	return history.can_undo()


func can_redo() -> bool:
	return history.can_redo()


func undo() -> bool:
	if not history.can_undo():
		return false
	var entry: History.Entry = history.peek_undo()
	var result: CommandResult = _send_ops(entry.inverse, entry.tx)
	if not result.ok:
		last_error = result.error
		return false
	history.confirm_undo()
	last_error = ""
	changed.emit()
	return true


func redo() -> bool:
	if not history.can_redo():
		return false
	var entry: History.Entry = history.peek_redo()
	var result: CommandResult = _send_ops(entry.forward, entry.tx)
	if not result.ok:
		last_error = result.error
		return false
	history.confirm_redo()
	last_error = ""
	changed.emit()
	return true


func _send_ops(ops: Array[Dictionary], tx: String) -> CommandResult:
	var payload: Dictionary = {"ops": ops.duplicate(true)}
	var cmd: Command = Command.make("patch.apply", payload, ids.next_uuid(), tx, author)
	return channel.submit(cmd)


func _rollback(applied: Array[Dictionary], tx: String) -> void:
	if not applied.is_empty():
		_send_ops(Patch.invert(applied), tx)


func _fail(message: String) -> CommandResult:
	last_error = message
	return CommandResult.failure(message)
