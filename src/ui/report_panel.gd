class_name ReportPanel
extends PanelContainer
## The report (SRD section 9): the issues of the project with their counts. Entirely optional, never
## blocks anything. While the list has the focus, `Tab` shows the next open issue and `Enter`
## acknowledges the selected one (FR-RPT-3, FR-RPT-9); clicking an issue shows its subject.

const MAX_LIST_HEIGHT: float = 170.0

var model: EditorModel

var list: ItemList
var _title: Label
var _signature: String = ""
var _shown: Array[Issue] = []
var _syncing: bool = false


func _init() -> void:
	theme_type_variation = "ToolPanel"
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	_title = Label.new()
	_title.add_theme_color_override("font_color", AppTheme.BLUE)
	column.add_child(_title)
	list = ItemList.new()
	list.name = "issues"
	list.focus_mode = Control.FOCUS_ALL
	list.custom_minimum_size = Vector2(0, MAX_LIST_HEIGHT)
	list.allow_reselect = true
	list.item_selected.connect(_on_item_selected)
	list.gui_input.connect(_on_list_input)
	column.add_child(list)
	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	var next: Button = Button.new()
	next.text = "Suivant"
	next.name = "next"
	next.focus_mode = Control.FOCUS_NONE
	next.tooltip_text = "Problème suivant (Tab dans la liste)"
	next.pressed.connect(func() -> void: model.go_next_issue())
	buttons.add_child(next)
	var ack: Button = Button.new()
	ack.text = "Reconnaître"
	ack.name = "acknowledge"
	ack.focus_mode = Control.FOCUS_NONE
	ack.tooltip_text = "Reconnaître le problème choisi (Entrée dans la liste)"
	ack.pressed.connect(func() -> void: model.acknowledge_selected_issue())
	buttons.add_child(ack)
	var undo: Button = Button.new()
	undo.text = "Rouvrir"
	undo.name = "reopen"
	undo.focus_mode = Control.FOCUS_NONE
	undo.tooltip_text = "Rouvrir un problème reconnu"
	undo.pressed.connect(func() -> void:
		var issue: Issue = model.selected_issue()
		if issue != null:
			model.unacknowledge_issue(issue.key))
	buttons.add_child(undo)


func bind(p_model: EditorModel) -> void:
	if model != null and model.changed.is_connected(refresh):
		model.changed.disconnect(refresh)
	model = p_model
	model.changed.connect(refresh)
	_signature = ""
	refresh()


## Puts the keyboard focus in the list, so Tab and Enter work (palette: "Rapport : parcourir").
func browse() -> void:
	model.set_report_visible(true)
	list.grab_focus()
	if model.selected_issue() == null:
		model.go_next_issue()


func refresh() -> void:
	if model == null:
		return
	visible = model.report_visible
	var signature: String = "%d|%s|%s" % [model.doc().revision, model.selected_issue_key, str(model.report_visible)]
	if signature == _signature:
		return
	_signature = signature
	_rebuild()


func _rebuild() -> void:
	_syncing = true
	list.clear()
	_shown = model.issues()
	var errors: int = 0
	var warnings: int = 0
	var done: int = 0
	for issue: Issue in _shown:
		if issue.acknowledged:
			done += 1
		elif issue.is_error():
			errors += 1
		else:
			warnings += 1
		var mark: String = "✓" if issue.acknowledged else ("✖" if issue.is_error() else "⚠")
		var index: int = list.add_item("%s  %s" % [mark, issue.message])
		list.set_item_tooltip(index, issue.message)
		if issue.acknowledged:
			list.set_item_custom_fg_color(index, AppTheme.OVERLAY0)
		elif issue.is_error():
			list.set_item_custom_fg_color(index, AppTheme.RED)
		if issue.key == model.selected_issue_key:
			list.select(index)
	_title.text = "Rapport — %d erreur(s), %d avertissement(s)%s" % [errors, warnings, ", %d reconnu(s)" % done if done > 0 else ""]
	_syncing = false


func _on_item_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _shown.size():
		return
	model.goto_issue(_shown[index])


## Tab: next issue. Enter: acknowledge. Only here, while the list has the focus.
func _on_list_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.ctrl_pressed or key.alt_pressed:
		return
	if key.keycode == KEY_TAB:
		model.go_next_issue()
		list.accept_event()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		model.acknowledge_selected_issue()
		list.accept_event()
