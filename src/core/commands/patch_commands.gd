class_name PatchCommands
extends RefCounted
## Handler for patch.apply: replays raw operations. This is how undo and redo travel as
## ordinary commands (SRD ARCH-5), and it works unchanged with a remote resolver.


## payload: {ops: [...]}. The Resolver applies them with before-state checking.
static func apply(_doc: Document, payload: Dictionary) -> BuildResult:
	if not JsonUtil.has_array(payload, "ops"):
		return BuildResult.fail("patch.apply needs ops")
	var raw: Array = payload["ops"]
	var problem: String = Patch.validate_ops(raw)
	if not problem.is_empty():
		return BuildResult.fail(problem)
	var ops: Array[Dictionary] = []
	ops.assign(raw.duplicate(true))
	return BuildResult.success(ops)
