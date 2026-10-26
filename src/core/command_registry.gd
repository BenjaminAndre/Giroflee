class_name CommandRegistry
extends RefCounted
## Maps a command type to its handler: Callable(doc: Document, payload: Dictionary) -> BuildResult.

static var _handlers: Dictionary = {}


static func handler_for(type: String) -> Callable:
	_ensure()
	if _handlers.has(type):
		var handler: Callable = _handlers[type]
		return handler
	return Callable()


static func types() -> PackedStringArray:
	_ensure()
	var names: PackedStringArray = PackedStringArray()
	for key: Variant in _handlers.keys():
		var name: String = key
		names.append(name)
	names.sort()
	return names


static func _ensure() -> void:
	if not _handlers.is_empty():
		return
	_handlers = {
		"sheet.add": SheetCommands.add,
		"sheet.update": SheetCommands.update,
		"sheet.remove": SheetCommands.remove,
		"sheet.move": SheetCommands.move,
		"entity.add": EntityCommands.add,
		"entity.update": EntityCommands.update,
		"entity.remove": EntityCommands.remove,
		"entity.move": EntityCommands.move,
		"doc.set": ValueCommands.set_value,
		"doc.unset": ValueCommands.unset,
		"patch.apply": PatchCommands.apply,
	}
