class_name CommandResult
extends RefCounted
## Outcome of submitting a command.

var ok: bool = false
var error: String = ""
## The committed patch (null on failure).
var patch: Patch = null


static func success(p_patch: Patch) -> CommandResult:
	var result: CommandResult = CommandResult.new()
	result.ok = true
	result.patch = p_patch
	return result


static func failure(message: String) -> CommandResult:
	var result: CommandResult = CommandResult.new()
	result.ok = false
	result.error = message
	return result
