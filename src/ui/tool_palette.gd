class_name ToolPalette
extends PanelContainer
## The vertical tool bar at the left of the canvas (SRD FR-TOOLBAR): one icon-only button per tool,
## with a tooltip that names the tool and its hot key. It follows the keyboard: pressing `W`
## presses the wall button. It is for people who do not know the hot keys yet.

const ICON_PX: int = 22
const BUTTON_PX: int = 40

## {id, tooltip}: the tooltip names the hot key approved in SRD section 7.
const TOOLS: Array[Dictionary] = [
	{"id": "select", "tip": "Sélection (Échap)"},
	{"id": "wall", "tip": "Mur (W)"},
	{"id": "door", "tip": "Porte (D)"},
	{"id": "window", "tip": "Fenêtre (F)"},
	{"id": "stair", "tip": "Escalier (E)"},
	{"id": "block", "tip": "Bloc gris (S)"},
	{"id": "text", "tip": "Texte (T)"},
]

var model: EditorModel

var _buttons: Dictionary = {}
var _group: ButtonGroup = ButtonGroup.new()


func _init() -> void:
	theme_type_variation = "ToolPanel"
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	for tool: Dictionary in TOOLS:
		var tool_id: String = tool["id"]
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.icon = IconLibrary.texture(tool_id, ICON_PX)
		button.expand_icon = false
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size = Vector2(BUTTON_PX, BUTTON_PX)
		button.tooltip_text = tool["tip"]
		button.pressed.connect(_on_pressed.bind(tool_id))
		column.add_child(button)
		_buttons[tool_id] = button


func bind(p_model: EditorModel) -> void:
	if model != null and model.changed.is_connected(sync):
		model.changed.disconnect(sync)
	model = p_model
	model.changed.connect(sync)
	sync()


func button_for(tool_id: String) -> Button:
	if _buttons.has(tool_id):
		var button: Button = _buttons[tool_id]
		return button
	return null


## Presses the button of the active tool (and only that one).
func sync() -> void:
	if model == null:
		return
	for tool_id: Variant in _buttons.keys():
		var button: Button = _buttons[tool_id]
		button.set_pressed_no_signal(str(tool_id) == model.tool_name)


func _on_pressed(tool_id: String) -> void:
	if model != null:
		model.set_tool(tool_id)
	sync()
