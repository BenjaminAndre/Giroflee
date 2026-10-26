class_name InProcessChannel
extends CommandChannel
## Channel whose resolver lives in the same process; submission is synchronous.

var resolver: Resolver


func _init(document: Document) -> void:
	resolver = Resolver.new(document)
	resolver.committed.connect(_on_committed)


func submit(command: Command) -> CommandResult:
	return resolver.submit(command)


func get_document() -> Document:
	return resolver.document


func _on_committed(patch: Patch) -> void:
	committed.emit(patch)
