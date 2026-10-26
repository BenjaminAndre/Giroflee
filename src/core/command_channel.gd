class_name CommandChannel
extends RefCounted
## Interface between a client session and a resolver (SRD ARCH-6). v0.1 only has the
## in-process implementation; nothing above this interface may assume the resolver is local
## or that `committed` arrives synchronously.

signal committed(patch: Patch)


func submit(_command: Command) -> CommandResult:
	return CommandResult.failure("CommandChannel.submit is abstract")


## Read access to the document. Callers must treat it as read-only.
func get_document() -> Document:
	return null
