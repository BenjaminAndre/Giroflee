class_name BuildResult
extends RefCounted
## What a command handler returns: either an error, or the operations to apply.
## Handlers are pure functions of (document, payload); they never mutate the document.

var error: String = ""
var ops: Array[Dictionary] = []


static func fail(message: String) -> BuildResult:
	var result: BuildResult = BuildResult.new()
	result.error = message
	return result


static func success(p_ops: Array[Dictionary]) -> BuildResult:
	var result: BuildResult = BuildResult.new()
	result.ops = p_ops
	return result
