class_name UnifilaireTool
extends Tool
## The only tool on the unifilaire (SRD FR-TAB-5, FR-UNI-1, FR-UNI-7). The drawing itself is computed
## and read-only: a click on a point shows its first symbol on the plan, a click on a column header,
## a bus device or a head item selects it (the Properties panel edits it), and dragging a column or a
## device sideways reorders the bus.

const DRAG_START_MM: float = 2.0

var _layout: UnifilaireLayout = null
var _bus_index: int = -1
var _press_page: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drop_at: int = -1


func tool_name() -> String:
	return "select"


func is_active() -> bool:
	return _bus_index >= 0


func press(model: EditorModel, input: ToolInput) -> void:
	_layout = _current_layout(model)
	var page: Vector2 = _page(model, input.world)
	var region: UnifilaireLayout.Region = _layout.hit(page)
	_bus_index = -1
	_dragging = false
	if region == null:
		model.select_uni({})
		return
	match region.kind:
		"point":
			model.select_uni({"kind": "point", "letter": region.letter, "index": region.index})
			if not region.symbol_ids.is_empty():
				model.jump_to_symbol(region.symbol_ids[0])
		"column", "device":
			model.select_uni({"kind": region.kind, "letter": region.letter, "id": region.id})
			_bus_index = _bus_index_of(region)
			_press_page = page
		"head":
			model.select_uni({"kind": "head", "id": region.id})


func move(model: EditorModel, input: ToolInput) -> void:
	if _bus_index < 0 or _layout == null:
		return
	var page: Vector2 = _page(model, input.world)
	if not _dragging and absf(page.x - _press_page.x) < DRAG_START_MM:
		return
	_dragging = true
	_drop_at = _layout.insertion_index(page.x)
	model.changed.emit()


func release(model: EditorModel, _input: ToolInput) -> void:
	var from_index: int = _bus_index
	var to_index: int = _drop_at
	var moved: bool = _dragging
	_bus_index = -1
	_dragging = false
	_drop_at = -1
	if moved and from_index >= 0 and to_index >= 0:
		model.move_bus_item(from_index, to_index)
	model.changed.emit()


func cancel(model: EditorModel) -> bool:
	if _bus_index < 0:
		return false
	_bus_index = -1
	_dragging = false
	_drop_at = -1
	model.changed.emit()
	return true


func render_options(model: EditorModel) -> Dictionary:
	var options: Dictionary = {}
	if not model.uni_selection.is_empty():
		options["selected"] = model.uni_selection
	if _dragging and _drop_at >= 0:
		options["drop_at"] = _drop_at
	return options


func hint(_model: EditorModel) -> String:
	return "Unifilaire : clic sur un point = voir le symbole sur le plan · clic sur un circuit ou un appareil = le modifier · glisser = réordonner la barre"


func _current_layout(model: EditorModel) -> UnifilaireLayout:
	var derived: UniModel = UnifilaireBuilder.derive(model.doc())
	return UnifilaireLayout.compute(model.doc(), model.sheet(), derived)


## World position (y up) to page millimetres from the top-left corner.
func _page(model: EditorModel, world: Vector2) -> Vector2:
	var scale_den: float = model.ctx().scale
	var paper_h: int = model.sheet().props["paper_h_mm"]
	return Vector2(world.x / scale_den, float(paper_h) - world.y / scale_den)


## Which bus slot a column or device region belongs to.
func _bus_index_of(region: UnifilaireLayout.Region) -> int:
	for i: int in _layout.model.bus.size():
		var item: UniModel.BusItem = _layout.model.bus[i]
		if region.kind == "device" and item.is_device and item.id == region.id:
			return i
		if region.kind == "column" and not item.is_device and _layout.model.columns[item.column].letter == region.letter:
			return i
	return -1
