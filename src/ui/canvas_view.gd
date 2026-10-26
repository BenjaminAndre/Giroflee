class_name CanvasView
extends Control
## The drawing surface: draws the sheet's DrawList (the same one the exports will use), the
## workspace, page, dot grid, A4/A3 hints, selection and tool previews, and forwards pointer
## input to the EditorInput. All geometry lives in world mm; this class only maps it to pixels.

const WORKSPACE: Color = Color(0.72, 0.74, 0.77)
const PAGE_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.18)
const SELECTION: Color = Color(0.1, 0.46, 0.82)
const HINT: Color = Color(0.35, 0.45, 0.62, 0.8)
const MIN_DOT_SPACING_PX: float = 8.0

var model: EditorModel
var input: EditorInput
var font: Font = ThemeDB.fallback_font

var _cached_list: DrawList = null
var _cached_revision: int = -1
var _cached_sheet: String = ""


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind(p_model: EditorModel, p_input: EditorInput) -> void:
	if model != null and model.changed.is_connected(queue_redraw):
		model.changed.disconnect(queue_redraw)
	model = p_model
	input = p_input
	model.changed.connect(queue_redraw)
	_cached_list = null
	model.set_viewport_size(size)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and model != null:
		model.set_viewport_size(size)


func _gui_input(event: InputEvent) -> void:
	if input == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		grab_focus()
	if input.handle(event):
		accept_event()


func _draw() -> void:
	if model == null:
		return
	var view: ViewTransform = model.view()
	draw_rect(Rect2(Vector2.ZERO, size), WORKSPACE)
	_draw_page(view)
	_draw_list(_sheet_list(), view, 1.0)
	_draw_selection(view)
	_draw_list(model.preview_list(), view, 0.85)
	_draw_snap_marker(view)
	if model.tool.has_overlay_rect():
		_draw_box(view, model.tool.overlay_rect())


# --- background ---------------------------------------------------------------------------


func _draw_page(view: ViewTransform) -> void:
	var sheet: Sheet = model.sheet()
	var page: Rect2 = FrameBuilder.page_rect(sheet)
	var top_left: Vector2 = view.world_to_screen(Vector2(page.position.x, page.end.y))
	var bottom_right: Vector2 = view.world_to_screen(Vector2(page.end.x, page.position.y))
	var rect: Rect2 = Rect2(top_left, bottom_right - top_left)
	draw_rect(Rect2(rect.position + Vector2(4, 4), rect.size), PAGE_SHADOW)
	draw_rect(rect, Color.WHITE)
	_draw_grid(view, sheet, page)
	var hints: bool = sheet.props["hints"]
	if hints:
		_draw_hint(view, sheet, 297.0, 210.0, "A4")
		_draw_hint(view, sheet, 420.0, 297.0, "A3")


func _draw_grid(view: ViewTransform, sheet: Sheet, page: Rect2) -> void:
	var step_value: int = sheet.props["grid_step_mm"]
	var step: float = float(step_value)
	var factor: float = 1.0
	while step * factor * view.zoom < MIN_DOT_SPACING_PX and factor < 1024.0:
		factor *= 2.0
	step *= factor
	var visible: Rect2 = view.visible_world_rect().intersection(page)
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	var x0: float = ceilf(visible.position.x / step) * step
	var y0: float = ceilf(visible.position.y / step) * step
	var x: float = x0
	while x <= visible.end.x:
		var y: float = y0
		while y <= visible.end.y:
			var p: Vector2 = view.world_to_screen(Vector2(x, y))
			draw_rect(Rect2(p - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), PlanTheme.DOT)
			y += step
		x += step


## Dashed outline of an A-series page (landscape, at the sheet's scale) from the page's top-left.
func _draw_hint(view: ViewTransform, sheet: Sheet, w_mm: float, h_mm: float, label: String) -> void:
	var scale: int = sheet.props["scale_den"]
	var page: Rect2 = FrameBuilder.page_rect(sheet)
	var a: Vector2 = view.world_to_screen(Vector2(page.position.x, page.end.y))
	var b: Vector2 = view.world_to_screen(Vector2(page.position.x + w_mm * float(scale), page.end.y - h_mm * float(scale)))
	var corners: PackedVector2Array = PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a])
	for i: int in range(corners.size() - 1):
		draw_dashed_line(corners[i], corners[i + 1], HINT, 1.0, 8.0)
	draw_string(font, Vector2(b.x - 26.0, b.y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HINT)


# --- DrawList -----------------------------------------------------------------------------


func _sheet_list() -> DrawList:
	var overrides: Dictionary = model.tool.overrides(model)
	if overrides.is_empty() and _cached_list != null and _cached_revision == model.revision and _cached_sheet == model.active_sheet_id:
		return _cached_list
	var list: DrawList = model.page_list()
	if overrides.is_empty():
		_cached_list = list
		_cached_revision = model.revision
		_cached_sheet = model.active_sheet_id
	return list


func _draw_list(list: DrawList, view: ViewTransform, alpha: float) -> void:
	for op: DrawOp in list.ops:
		match op.kind:
			DrawOp.POLYGON:
				_draw_polygon_op(op, view, alpha)
			DrawOp.POLYLINE:
				_draw_polyline_op(op, view, alpha)
			DrawOp.TEXT:
				_draw_text_op(op, view, alpha)


func _to_screen(points: PackedVector2Array, view: ViewTransform) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in points:
		out.append(view.world_to_screen(p))
	return out


func _draw_polygon_op(op: DrawOp, view: ViewTransform, alpha: float) -> void:
	if op.points.size() < 3:
		return
	var screen: PackedVector2Array = _to_screen(op.points, view)
	var fill: Color = op.fill
	fill.a *= alpha
	if fill.a > 0.0 and _polygon_area(screen) > 0.05:
		draw_colored_polygon(screen, fill)


func _draw_polyline_op(op: DrawOp, view: ViewTransform, alpha: float) -> void:
	if op.points.size() < 2:
		return
	var screen: PackedVector2Array = _to_screen(op.points, view)
	if op.closed:
		screen.append(screen[0])
	var color: Color = op.color
	color.a *= alpha
	draw_polyline(screen, color, maxf(1.0, op.width * view.zoom), true)


func _draw_text_op(op: DrawOp, view: ViewTransform, alpha: float) -> void:
	var px: float = op.size * view.zoom
	if px < 5.0 or op.text.is_empty():
		return
	var origin: Vector2 = view.world_to_screen(op.points[0])
	var font_size: int = clampi(roundi(px), 5, 512)
	var color: Color = op.color
	color.a *= alpha
	var width: float = font.get_string_size(op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var dx: float = 0.0
	if op.anchor == "center":
		dx = -width * 0.5
	elif op.anchor == "right":
		dx = -width
	draw_set_transform(origin, -deg_to_rad(op.rotation_deg), Vector2.ONE)
	draw_string(font, Vector2(dx, 0.0), op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if op.bold:
		draw_string(font, Vector2(dx + 1.0, 0.0), op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _polygon_area(points: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i: int in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


# --- overlays -----------------------------------------------------------------------------


func _draw_selection(view: ViewTransform) -> void:
	var context: RenderContext = model.ctx()
	for entity: Entity in model.selected_entities():
		var bounds: Rect2 = EntityGeometry.bounds(entity, context)
		_draw_box(view, bounds.grow(6.0 / view.zoom), entity.type != "wall")
	if model.tool_name == "select":
		for handle: Dictionary in SelectTool.handles_for(model):
			var pos: Vector2 = handle["pos"]
			var p: Vector2 = view.world_to_screen(pos)
			var box: Rect2 = Rect2(p - Vector2(4.5, 4.5), Vector2(9, 9))
			draw_rect(box, Color.WHITE)
			draw_rect(box, SELECTION, false, 1.5)


func _draw_box(view: ViewTransform, world_rect: Rect2, tint: bool = true) -> void:
	var a: Vector2 = view.world_to_screen(Vector2(world_rect.position.x, world_rect.end.y))
	var b: Vector2 = view.world_to_screen(Vector2(world_rect.end.x, world_rect.position.y))
	var rect: Rect2 = Rect2(a, b - a).abs()
	if tint:
		draw_rect(rect, Color(SELECTION.r, SELECTION.g, SELECTION.b, 0.08))
	draw_rect(rect, SELECTION, false, 1.2)


func _draw_snap_marker(view: ViewTransform) -> void:
	if model.hover_snap == null or model.tool_name == "select":
		return
	var p: Vector2 = view.world_to_screen(model.hover_snap.pos)
	var color: Color = Color(0.95, 0.5, 0.1) if model.hover_snap.kind in [SnapEngine.VERTEX, SnapEngine.MIDPOINT] else Color(0.3, 0.3, 0.3, 0.7)
	draw_arc(p, 5.0, 0.0, TAU, 16, color, 1.4, true)
	draw_line(p - Vector2(8, 0), p + Vector2(8, 0), color, 1.0)
	draw_line(p - Vector2(0, 8), p + Vector2(0, 8), color, 1.0)
