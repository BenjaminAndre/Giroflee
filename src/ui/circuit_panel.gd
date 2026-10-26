class_name CircuitPanel
extends PanelContainer
## The circuits in use, with their colour and number of points (SRD FR-FOCUS). A click on a row greys
## the circuit out (or shows it again), a double-click makes it the only visible one, and a double-click
## on that circuit brings back what was visible before. The active circuit, the one new symbols join,
## is marked; it is changed with C and a letter. Focus is view state: nothing here touches the project.

const SWATCH_PX: int = 14

var model: EditorModel

var _rows: VBoxContainer
var _signature: String = ""


func _init() -> void:
	theme_type_variation = "ToolPanel"
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	var title: Label = Label.new()
	title.text = "Circuits"
	title.add_theme_color_override("font_color", AppTheme.BLUE)
	column.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	column.add_child(_rows)


func bind(p_model: EditorModel) -> void:
	if model != null and model.changed.is_connected(refresh):
		model.changed.disconnect(refresh)
	model = p_model
	model.changed.connect(refresh)
	_signature = ""
	refresh()


## Letters listed: those in use plus the active one.
func letters() -> Array[String]:
	var out: Array[String] = Numbering.circuits_in_use(model.doc())
	if not out.has(model.active_circuit):
		out.append(model.active_circuit)
		out.sort()
	return out


func refresh() -> void:
	if model == null:
		return
	var shown: Array[String] = letters()
	var signature: String = "%d|%s|%s|%s" % [model.revision, ",".join(PackedStringArray(shown)), ",".join(PackedStringArray(model.focus.dimmed_letters())), model.active_circuit]
	if signature == _signature:
		return
	_signature = signature
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	visible = true
	for letter: String in shown:
		_rows.add_child(_make_row(letter))


## Row of one circuit; also the thing tests click.
func row_for(letter: String) -> Control:
	for child: Node in _rows.get_children():
		if child.name == "row_%s" % letter:
			var row: Control = child
			return row
	return null


func _make_row(letter: String) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.name = "row_%s" % letter
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmed: bool = model.focus.is_dimmed(letter)
	var active: bool = letter == model.active_circuit
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var swatch: ColorRect = ColorRect.new()
	swatch.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
	swatch.color = PlanTheme.GHOST if dimmed else CircuitPalette.color(letter)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(swatch)
	var name_label: Label = Label.new()
	name_label.text = ("▶ %s" if active else "  %s") % letter
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	var points: Label = Label.new()
	var count: int = Numbering.point_count(model.doc(), letter)
	points.text = "%d point%s" % [count, "s" if count > 1 else ""]
	points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dimmed:
		points.add_theme_color_override("font_color", AppTheme.OVERLAY0)
		name_label.add_theme_color_override("font_color", AppTheme.OVERLAY0)
	line.add_child(points)
	row.tooltip_text = "Clic : griser ou afficher · double-clic : isoler · C puis lettre : circuit actif"
	row.gui_input.connect(_on_row_input.bind(letter))
	return row


func _on_row_input(event: InputEvent, letter: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	click_circuit(letter, button.double_click)


## What a click (or, with `double`, the second press of a double-click) on a circuit does.
func click_circuit(letter: String, double: bool) -> void:
	if double:
		# the first press of the double-click already toggled it: undo that, then solo
		model.focus_toggle(letter)
		model.focus_solo(letter, letters())
	else:
		model.focus_toggle(letter)
