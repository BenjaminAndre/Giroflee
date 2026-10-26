class_name PaletteOverlay
extends PanelContainer
## The command palette (Ctrl+P): a search field over the list of commands, fuzzy matching, Up
## and Down to choose, Enter to run, Escape to close (SRD FR-KEY-1).

signal closed

const MAX_ROWS: int = 12

var entries: Array[EditorCommands.Entry] = []

var _field: LineEdit
var _list: ItemList
var _shown: Array[int] = []


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(520, 0)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	_field = LineEdit.new()
	_field.placeholder_text = "Tapez une commande…"
	_field.text_changed.connect(_on_text_changed)
	_field.text_submitted.connect(func(_t: String) -> void: _run_selected())
	_field.gui_input.connect(_on_field_input)
	box.add_child(_field)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 280)
	_list.item_activated.connect(func(_i: int) -> void: _run_selected())
	box.add_child(_list)


func open(p_entries: Array[EditorCommands.Entry]) -> void:
	entries = p_entries
	_field.text = ""
	_refresh("")
	visible = true
	_field.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_text_changed(text: String) -> void:
	_refresh(text)


func _refresh(query: String) -> void:
	_shown = EditorCommands.search(entries, query)
	_list.clear()
	for i: int in mini(_shown.size(), MAX_ROWS):
		var entry: EditorCommands.Entry = entries[_shown[i]]
		var line: String = entry.title if entry.shortcut.is_empty() else "%s    [%s]" % [entry.title, entry.shortcut]
		_list.add_item(line)
	if _list.item_count > 0:
		_list.select(0)


func _on_field_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed:
		return
	var count: int = _list.item_count
	match key.keycode:
		KEY_ESCAPE:
			close()
			_field.accept_event()
		KEY_DOWN:
			if count > 0:
				_list.select(mini(_selected() + 1, count - 1))
			_field.accept_event()
		KEY_UP:
			if count > 0:
				_list.select(maxi(_selected() - 1, 0))
			_field.accept_event()


func _selected() -> int:
	var picked: PackedInt32Array = _list.get_selected_items()
	return picked[0] if not picked.is_empty() else 0


func _run_selected() -> void:
	if _list.item_count == 0:
		return
	var index: int = _selected()
	var entry: EditorCommands.Entry = entries[_shown[index]]
	close()
	entry.action.call()
