class_name QuickbarView
extends PanelContainer
## The nine quickbar slots (SRD FR-QB-2) in a strip above the status bar: the key number, the icon of
## the stored tool, the slot of the active tool outlined. A click uses the slot, like its key.

const ICON_PX: int = 18

var model: EditorModel

var _buttons: Array[Button] = []


func _init() -> void:
	theme_type_variation = "ToolPanel"
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var title: Label = Label.new()
	title.text = "Barre rapide"
	title.add_theme_color_override("font_color", AppTheme.SUBTEXT0)
	row.add_child(title)
	for slot: int in range(1, Quickbar.SLOTS + 1):
		var button: Button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(58, 30)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: model.use_quickbar(slot))
		row.add_child(button)
		_buttons.append(button)


func bind(p_model: EditorModel) -> void:
	if model != null and model.changed.is_connected(sync):
		model.changed.disconnect(sync)
	model = p_model
	model.changed.connect(sync)
	sync()


func button_for(slot: int) -> Button:
	return _buttons[slot - 1]


func sync() -> void:
	if model == null:
		return
	for slot: int in range(1, Quickbar.SLOTS + 1):
		var button: Button = _buttons[slot - 1]
		var filled: bool = model.quickbar.is_filled(slot)
		button.text = str(slot)
		button.icon = null
		button.tooltip_text = "Case %d : vide (palette de commandes : « Barre rapide »)" % slot
		if filled:
			var preset: Dictionary = model.quickbar.preset(slot)
			var tool: String = preset["tool"]
			button.tooltip_text = "Case %d : %s" % [slot, tool]
			if IconLibrary.names().has(tool):
				button.icon = IconLibrary.texture(tool, ICON_PX)
		button.set_pressed_no_signal(filled and str(model.quickbar.preset(slot)["tool"]) == model.tool_name)
		button.modulate = Color.WHITE if filled else Color(1, 1, 1, 0.55)
