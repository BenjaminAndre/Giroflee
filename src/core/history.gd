class_name History
extends RefCounted
## Client-side undo/redo stack. Each entry is one transaction (one user gesture) stored as
## its forward operations and the inverse operations (SRD ARCH-5). Undo and redo are sent
## to the resolver as ordinary `patch.apply` commands by the Session.


class Entry:
	extends RefCounted
	var tx: String = ""
	var forward: Array[Dictionary] = []
	var inverse: Array[Dictionary] = []


var _undo_stack: Array[Entry] = []
var _redo_stack: Array[Entry] = []


## Records a committed transaction. A no-op transaction (no operations) is not recorded.
## Recording clears the redo stack.
func record(tx: String, forward: Array[Dictionary]) -> void:
	if forward.is_empty():
		return
	var entry: Entry = Entry.new()
	entry.tx = tx
	entry.forward = forward
	entry.inverse = Patch.invert(forward)
	_undo_stack.append(entry)
	_redo_stack.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo_depth() -> int:
	return _undo_stack.size()


func redo_depth() -> int:
	return _redo_stack.size()


func peek_undo() -> Entry:
	return _undo_stack.back()


func peek_redo() -> Entry:
	return _redo_stack.back()


## Marks the top undo entry as undone (call after its inverse was applied).
func confirm_undo() -> void:
	_redo_stack.append(_undo_stack.pop_back())


## Marks the top redo entry as redone (call after its forward ops were applied).
func confirm_redo() -> void:
	_undo_stack.append(_redo_stack.pop_back())


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
