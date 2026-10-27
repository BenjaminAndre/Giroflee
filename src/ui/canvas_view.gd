class_name CanvasView
extends Control
## The drawing surface: draws the sheet's DrawList (the same one the exports will use), the
## workspace, page, dot grid, A4/A3 hints, selection and tool previews, and forwards pointer
## input to the EditorInput. All geometry lives in world mm; this class only maps it to pixels.

const WORKSPACE: Color = AppTheme.CRUST
const PAGE_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.18)
const SELECTION: Color = Color(0.118, 0.4, 0.961)
const HINT: Color = Color(0.35, 0.45, 0.62, 0.8)
const MIN_DOT_SPACING_PX: float = 8.0

var model: EditorModel
var input: EditorInput
var font: Font = ThemeDB.fallback_font

## The Vulkan "Mobile" renderer multisamples 2D (project setting msaa_2d), which is what makes
## diagonal walls smooth. The OpenGL Compatibility renderer cannot, so there (fallback for
## machines without Vulkan) every filled polygon gets a feathered one-pixel outline instead.
var aa_edges: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
## The dot grid is a screen decoration; tests switch it off to measure edges.
var show_grid: bool = true

var _cached_list: DrawList = null
var _cached_revision: int = -1
var _cached_sheet: String = ""
var _cached_view_revision: int = -1


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
	_draw_list(model.preview_list(), view, 1.0)
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
	var hints: bool = model.doc().config["hints"]
	if hints:
		_draw_hint(view, sheet, 297.0, 210.0, "A4")
		_draw_hint(view, sheet, 420.0, 297.0, "A3")


func _draw_grid(view: ViewTransform, sheet: Sheet, page: Rect2) -> void:
	if not show_grid:
		return
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
			var p: Vector2 = view.world_to_screen(Vector2(x, y)).round()
			# whole-pixel squares stay crisp even with multisampling
			draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), PlanTheme.DOT)
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
	if overrides.is_empty() and not model.tool.is_active() and _cached_list != null and _cached_revision == model.revision and _cached_view_revision == model.view_revision and _cached_sheet == model.active_sheet_id:
		return _cached_list
	var list: DrawList = model.page_list()
	if overrides.is_empty() and not model.tool.is_active():
		_cached_list = list
		_cached_revision = model.revision
		_cached_view_revision = model.view_revision
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
	if fill.a <= 0.0 or _polygon_area(screen) <= 0.05:
		return
	draw_colored_polygon(screen, fill)
	if aa_edges:
		var outline: PackedVector2Array = screen.duplicate()
		outline.append(screen[0])
		draw_polyline(outline, fill, 1.0, true)


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
	var entities: Array[Entity] = model.selected_entities()
	if entities.size() > 1:
		for entity: Entity in entities:
			_draw_box(view, EntityGeometry.bounds(entity, context).grow(4.0 / view.zoom), false, 0.5)
	if model.tool_name != "select":
		return
	var box: TransformBox = SelectTool.box_for(model)
	if box != null:
		_draw_transform_box(view, box)
	for handle: Dictionary in SelectTool.handles_for(model):
		var pos: Vector2 = handle["pos"]
		_draw_handle_square(view.world_to_screen(pos))
	_update_cursor()


## Affinity-style box: eight resize handles and a rotation handle on a stem above it.
func _draw_transform_box(view: ViewTransform, box: TransformBox) -> void:
	var a: Vector2 = view.world_to_screen(Vector2(box.box.position.x, box.box.end.y))
	var b: Vector2 = view.world_to_screen(Vector2(box.box.end.x, box.box.position.y))
	draw_rect(Rect2(a, b - a).abs(), SELECTION, false, 1.0)
	var top_middle: Vector2 = view.world_to_screen(box.handle_pos("n"))
	for handle: Dictionary in box.handles:
		var id: String = handle["id"]
		var pos: Vector2 = handle["pos"]
		var p: Vector2 = view.world_to_screen(pos)
		if id == "rotate":
			draw_line(top_middle, p, SELECTION, 1.0)
			draw_circle(p, 5.5, Color.WHITE)
			draw_arc(p, 5.5, 0.0, TAU, 20, SELECTION, 1.5, true)
		else:
			_draw_handle_square(p)


func _draw_handle_square(p: Vector2) -> void:
	var square: Rect2 = Rect2(p - Vector2(4.5, 4.5), Vector2(9, 9))
	draw_rect(square, Color.WHITE)
	draw_rect(square, SELECTION, false, 1.5)


func _update_cursor() -> void:
	match model.hover_handle:
		"nw", "se":
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		"ne", "sw":
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		"n", "s":
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		"e", "w":
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"rotate":
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		"vertex":
			mouse_default_cursor_shape = Control.CURSOR_MOVE
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


func _draw_box(view: ViewTransform, world_rect: Rect2, tint: bool = true, line_width: float = 1.2) -> void:
	var a: Vector2 = view.world_to_screen(Vector2(world_rect.position.x, world_rect.end.y))
	var b: Vector2 = view.world_to_screen(Vector2(world_rect.end.x, world_rect.position.y))
	var rect: Rect2 = Rect2(a, b - a).abs()
	if tint:
		draw_rect(rect, Color(SELECTION.r, SELECTION.g, SELECTION.b, 0.08))
	draw_rect(rect, SELECTION, false, line_width)


func _draw_snap_marker(view: ViewTransform) -> void:
	if model.hover_snap == null or model.tool_name == "select":
		return
	var p: Vector2 = view.world_to_screen(model.hover_snap.pos)
	var color: Color = Color(0.95, 0.5, 0.1) if model.hover_snap.kind in [SnapEngine.VERTEX, SnapEngine.MIDPOINT] else Color(0.3, 0.3, 0.3, 0.7)
	draw_arc(p, 5.0, 0.0, TAU, 16, color, 1.4, true)
	draw_line(p - Vector2(8, 0), p + Vector2(8, 0), color, 1.0)
	draw_line(p - Vector2(0, 8), p + Vector2(0, 8), color, 1.0)
