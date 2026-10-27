class_name UnifilaireRenderer
extends RefCounted
## Draws the unifilaire into a DrawList (SRD section 8). Everything comes from `UniModel` (what) and
## `UnifilaireLayout` (where); this class only turns them into lines, boxes, text and symbol artwork.
## The sheet's scale is 1, so world millimetres are page millimetres, y up.
##
## Options: {"selected": {"kind": "column"|"device"|"head"|"point", "letter", "index", "id"}} tints the
## selected thing; {"drop_at": int} draws the insertion mark of a column being dragged.

const LINE: float = 0.35
const DEFAULTED_TEXT: Color = Color(0.35, 0.35, 0.35)
const SELECTED_FILL: Color = Color(13.0 / 255.0, 121.0 / 255.0, 242.0 / 255.0, 0.14)


static func add(doc: Document, sheet: Sheet, ctx: RenderContext, options: Dictionary, out: DrawList) -> void:
	var model: UniModel = UnifilaireBuilder.derive(doc)
	var layout: UnifilaireLayout = UnifilaireLayout.compute(doc, sheet, model)
	var catalog: Catalog = Catalog.for_pack(doc.pack_ref)
	var library: SymbolLibrary = SymbolLibrary.for_pack(doc.pack_ref)
	var pen: Pen = Pen.new(sheet, ctx, out)

	if options.has("selected"):
		_add_selection(layout, options["selected"], pen)
	_add_head(model, layout, catalog, pen)
	_add_bus(model, layout, pen)
	for i: int in model.bus.size():
		var item: UniModel.BusItem = model.bus[i]
		if item.is_device:
			_add_device(item, layout, i, catalog, pen)
		else:
			_add_column(model.columns[item.column], layout, i, catalog, library, pen)
	_add_ruler(model, layout, pen)
	if options.has("drop_at"):
		var drop: int = options["drop_at"]
		var x: float = layout.slot_boundary(drop)
		pen.line([Vector2(x, layout.y_bus - UnifilaireLayout.HEADER_UP), Vector2(x, layout.y_rows0)], PlanTheme.BLUE, 0.8, "unifilaire_drop")


## Converts page millimetres (y down) to world ops.
class Pen:
	extends RefCounted
	var sheet: Sheet
	var ctx: RenderContext
	var out: DrawList

	func _init(p_sheet: Sheet, p_ctx: RenderContext, p_out: DrawList) -> void:
		sheet = p_sheet
		ctx = p_ctx
		out = p_out

	func world(page: Vector2) -> Vector2:
		return FrameBuilder.page_to_world(sheet, page.x, page.y)

	func line(points: Array, color: Color, width: float, layer: String = "unifilaire", entity_id: String = "") -> void:
		var path: PackedVector2Array = PackedVector2Array()
		for point: Variant in points:
			var page: Vector2 = point
			path.append(world(page))
		out.add(DrawOp.polyline(path, color, ctx.page_to_world(width), layer, entity_id))

	func box(rect: Rect2, color: Color, width: float, fill: Color = Color(0, 0, 0, 0), layer: String = "unifilaire", entity_id: String = "") -> void:
		var corners: PackedVector2Array = PackedVector2Array([
			world(rect.position), world(Vector2(rect.end.x, rect.position.y)), world(rect.end), world(Vector2(rect.position.x, rect.end.y)),
		])
		if fill.a > 0.0:
			out.add(DrawOp.polygon(corners, fill, layer, entity_id))
		out.add(DrawOp.polyline(corners, color, ctx.page_to_world(width), layer, entity_id, true))

	## Text centred on `centre` (page mm); `size_pt_factor` scales the base font size.
	func text(content: String, centre: Vector2, size_factor: float, color: Color = PlanTheme.BLACK, bold: bool = false, layer: String = "unifilaire", entity_id: String = "") -> void:
		var size: float = ctx.pt_to_world(ctx.font_size_pt * size_factor)
		var at: Vector2 = world(centre) - Vector2(0.0, size * 0.35)
		var op: DrawOp = DrawOp.label(content, at, size, color, layer, entity_id)
		op.anchor = "center"
		op.bold = bold
		out.add(op)

	## Text size (page mm) for `size_factor`, to fit text in a width.
	func em(size_factor: float) -> float:
		return ctx.pt_to_world(ctx.font_size_pt * size_factor)


static func _add_selection(layout: UnifilaireLayout, selected: Variant, pen: Pen) -> void:
	var wanted: Dictionary = selected
	var index: int = wanted.get("index", 0)
	var region: UnifilaireLayout.Region = layout.region_of(str(wanted.get("kind", "")), str(wanted.get("letter", "")), index, str(wanted.get("id", "")))
	if region != null:
		pen.box(region.rect, Color(0, 0, 0, 0), 0.0, SELECTED_FILL, "unifilaire_selection")


static func _add_head(model: UniModel, layout: UnifilaireLayout, catalog: Catalog, pen: Pen) -> void:
	if model.head.is_empty():
		pen.text("Tête de ligne ?", Vector2(layout.x_head + UnifilaireLayout.HEAD_W * 0.5, layout.y_bus), 0.7, PlanTheme.DARK_RED, false, "unifilaire_open")
		return
	var count: int = model.head.size()
	for j: int in count:
		var from_bus: int = count - 1 - j
		var box: Rect2 = layout.head_box(from_bus)
		var entry: Dictionary = model.head[j]
		var item: Catalog.Item = catalog.item(str(entry["catalog"]))
		var id: String = str(entry["id"])
		pen.box(box, PlanTheme.BLACK, LINE, Color.WHITE, "unifilaire", id)
		var label: String = item.label if item != null else str(entry["catalog"])
		var detail: String = item.detail if item != null else ""
		var centre: Vector2 = box.get_center()
		if detail.is_empty():
			pen.text(label, centre, 0.7, PlanTheme.BLACK, false, "unifilaire", id)
		else:
			pen.text(label, centre - Vector2(0.0, 2.2), 0.7, PlanTheme.BLACK, false, "unifilaire", id)
			pen.text(detail, centre + Vector2(0.0, 2.4), 0.6, PlanTheme.BLACK, false, "unifilaire", id)
		if from_bus > 0:
			var above: Rect2 = layout.head_box(from_bus - 1)
			pen.line([Vector2(centre.x, above.end.y), Vector2(centre.x, box.position.y)], PlanTheme.BLACK, LINE)
	var top: Rect2 = layout.head_box(0)
	pen.line([Vector2(top.end.x, layout.y_bus), Vector2(layout.x_cols0 - 3.0, layout.y_bus)], PlanTheme.BLACK, LINE)


static func _add_bus(model: UniModel, layout: UnifilaireLayout, pen: Pen) -> void:
	if model.bus.is_empty():
		return
	pen.line([Vector2(layout.x_cols0 - 3.0, layout.y_bus), Vector2(layout.bus_end() - layout.slot_w[layout.slot_w.size() - 1] * 0.5, layout.y_bus)], PlanTheme.BLACK, LINE * 2.0)


static func _add_device(item: UniModel.BusItem, layout: UnifilaireLayout, slot: int, catalog: Catalog, pen: Pen) -> void:
	var centre_x: float = layout.slot_x[slot] + layout.slot_w[slot] * 0.5
	var box: Rect2 = Rect2(centre_x - UnifilaireLayout.DEVICE_BOX_W * 0.5, layout.y_bus - UnifilaireLayout.DEVICE_BOX_H * 0.5, UnifilaireLayout.DEVICE_BOX_W, UnifilaireLayout.DEVICE_BOX_H)
	pen.box(box, PlanTheme.BLACK, LINE, Color.WHITE, "unifilaire", item.id)
	var entry: Catalog.Item = catalog.item(item.catalog)
	var label: String = entry.label if entry != null else item.catalog
	pen.text(label, box.get_center(), 0.7, PlanTheme.BLACK, false, "unifilaire", item.id)
	if entry != null and not entry.detail.is_empty():
		pen.text(entry.detail, Vector2(centre_x, box.end.y + 3.0), 0.6, PlanTheme.BLACK, false, "unifilaire", item.id)


static func _add_column(column: UniModel.Column, layout: UnifilaireLayout, slot: int, catalog: Catalog, library: SymbolLibrary, pen: Pen) -> void:
	var x: float = layout.slot_x[slot] + layout.slot_w[slot] * 0.5
	var width: float = layout.slot_w[slot]
	var y_bus: float = layout.y_bus
	# header: letter in its circuit colour, then the title on up to two lines
	pen.text(column.letter, Vector2(x, y_bus - UnifilaireLayout.LETTER_UP), 1.5, CircuitPalette.color(column.letter), true, "unifilaire", "")
	var title: String = column.title
	var shown: Color = PlanTheme.BLACK
	if title.is_empty() and column.spare:
		title = "Réserve"
		shown = DEFAULTED_TEXT
	elif column.title_proposed:
		shown = DEFAULTED_TEXT
	var lines: PackedStringArray = _wrap(title, maxi(4, int(width / (pen.em(0.8) * 0.55))))
	for k: int in mini(lines.size(), 2):
		pen.text(lines[k], Vector2(x, y_bus - UnifilaireLayout.TITLE_UP + float(k) * 4.0), 0.8, shown)
	# tap, breaker, cable
	pen.line([Vector2(x, y_bus), Vector2(x, y_bus + UnifilaireLayout.BREAKER_TOP)], PlanTheme.BLACK, LINE)
	var box: Rect2 = Rect2(x - UnifilaireLayout.BREAKER_W * 0.5, y_bus + UnifilaireLayout.BREAKER_TOP, UnifilaireLayout.BREAKER_W, UnifilaireLayout.BREAKER_H)
	pen.box(box, PlanTheme.BLACK, LINE, Color.WHITE)
	var breaker: Catalog.Item = catalog.item(column.breaker)
	var breaker_color: Color = DEFAULTED_TEXT if column.breaker_defaulted else PlanTheme.BLACK
	if breaker != null:
		pen.text(breaker.label, box.get_center() - Vector2(0.0, 2.6), 0.7, breaker_color)
		pen.text(breaker.detail, box.get_center() + Vector2(0.0, 2.8), 0.6, breaker_color)
	var cable: Catalog.Item = catalog.item(column.cable)
	if cable != null:
		var fit: float = minf(0.65, (width - 1.0) / (float(cable.label.length()) * pen.em(1.0) * 0.55))
		pen.text(cable.label, Vector2(x, y_bus + UnifilaireLayout.CABLE_Y), maxf(fit, 0.3), DEFAULTED_TEXT if column.cable_defaulted else PlanTheme.BLACK)
	# conductor down to the last row, then the points
	var last: int = column.highest_index()
	var bottom: float = layout.row_center(last) if last > 0 else y_bus + UnifilaireLayout.CONDUCTOR_TOP
	var text_top: float = y_bus + UnifilaireLayout.CABLE_Y - 2.4
	var text_bottom: float = y_bus + UnifilaireLayout.CONDUCTOR_TOP - 1.2
	pen.line([Vector2(x, box.end.y), Vector2(x, text_top)], PlanTheme.BLACK, LINE)
	if bottom > text_bottom:
		pen.line([Vector2(x, text_bottom), Vector2(x, bottom)], PlanTheme.BLACK, LINE)
	for point: UniModel.Point in column.sorted_points():
		_add_point(column, point, x, width, layout, library, pen)


static func _add_point(column: UniModel.Column, point: UniModel.Point, x: float, width: float, layout: UnifilaireLayout, library: SymbolLibrary, pen: Pen) -> void:
	var y: float = layout.row_center(point.index)
	var count: int = point.items.size()
	var pitch: float = minf(UnifilaireLayout.ITEM_PITCH, (width - 4.0) / float(maxi(count + (1 if point.is_open() else 0), 1)))
	var unit: float = pen.ctx.symbol_scale
	var previous_x: float = x
	var entity_id: String = point.symbol_ids[0] if not point.symbol_ids.is_empty() else ""
	for k: int in count:
		var item: UniModel.Item = point.items[k]
		var centre_x: float = x + 2.0 + pitch * (float(k) + 0.5)
		pen.line([Vector2(previous_x, y), Vector2(centre_x - pitch * 0.35, y)], PlanTheme.BLACK, LINE)
		var def: SymbolLibrary.Def = library.def(item.type)
		var origin: Vector2 = pen.world(Vector2(centre_x, y))
		if def != null:
			var shapes: Array[Dictionary] = SymbolGeometry.shapes_of(def.unifilaire, origin, 0.0, false, false, unit)
			SymbolGeometry.add_shape_ops(shapes, PlanTheme.BLACK, def, "unifilaire_symbols", entity_id, pen.out)
		if item.count > 1:
			pen.text("x%d" % item.count, Vector2(centre_x, y - 4.6), 0.6, PlanTheme.BLACK, false, "unifilaire", entity_id)
		previous_x = centre_x + pitch * 0.35
	if point.is_open():
		var mark_x: float = x + 2.0 + pitch * (float(count) + 0.5)
		pen.line([Vector2(previous_x, y), Vector2(mark_x - 1.5, y)], PlanTheme.BLACK, LINE)
		pen.text("?", Vector2(mark_x, y), 1.6, PlanTheme.DARK_RED, true, "unifilaire_open", entity_id)


static func _add_ruler(model: UniModel, layout: UnifilaireLayout, pen: Pen) -> void:
	for index: int in range(1, model.rows + 1):
		pen.text(str(index), Vector2(layout.x_ruler, layout.row_center(index)), 0.7, DEFAULTED_TEXT, false, "unifilaire_ruler")


## Greedy word wrap on spaces; a word longer than `chars` is cut.
static func _wrap(text: String, chars: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var current: String = ""
	for word: String in text.split(" ", false):
		var piece: String = word
		while piece.length() > chars:
			if not current.is_empty():
				lines.append(current)
				current = ""
			lines.append(piece.substr(0, chars))
			piece = piece.substr(chars)
		var joined: String = piece if current.is_empty() else "%s %s" % [current, piece]
		if joined.length() <= chars:
			current = joined
		else:
			lines.append(current)
			current = piece
	if not current.is_empty():
		lines.append(current)
	return lines
