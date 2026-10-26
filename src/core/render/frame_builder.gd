class_name FrameBuilder
extends RefCounted
## Border frame of a sheet (SRD FR-PLAN-8): numbered columns along the top, lettered rows
## down the left side. A count of 0 removes the band on that axis. The area at the bottom of
## the page stays free for the cartouche (M4). Everything is in world mm, y up; the page
## occupies [0, W*scale] x [0, H*scale] with its origin at the bottom-left corner.


static func page_rect(sheet: Sheet) -> Rect2:
	var w: int = sheet.props["paper_w_mm"]
	var h: int = sheet.props["paper_h_mm"]
	var den: int = sheet.props["scale_den"]
	return Rect2(0.0, 0.0, float(w * den), float(h * den))


## Page millimetres measured from the top-left corner to a world point (y up).
static func page_to_world(sheet: Sheet, page_x: float, page_y_from_top: float) -> Vector2:
	var h: int = sheet.props["paper_h_mm"]
	var den: int = sheet.props["scale_den"]
	return Vector2(page_x * float(den), (float(h) - page_y_from_top) * float(den))


static func column_label(index: int) -> String:
	return str(index + 1)


static func row_label(index: int) -> String:
	return char(65 + clampi(index, 0, 25))


static func build(sheet: Sheet, ctx: RenderContext, out: DrawList) -> void:
	var cols: int = ctx.frame_cols
	var rows: int = ctx.frame_rows
	if cols == 0 and rows == 0:
		return
	var paper_w: int = sheet.props["paper_w_mm"]
	var paper_h: int = sheet.props["paper_h_mm"]
	var w: float = float(paper_w)
	var h: float = float(paper_h)
	var top_band: float = PlanTheme.FRAME_BAND if cols > 0 else 0.0
	var left_band: float = PlanTheme.FRAME_BAND if rows > 0 else 0.0
	var bottom: float = PlanTheme.CARTOUCHE_HEIGHT
	var line: float = ctx.page_to_world(PlanTheme.FRAME_LINE)
	var size: float = ctx.pt_to_world(ctx.font_size_pt)

	# outer border of the frame area (page mm measured from the top-left corner)
	var outer: PackedVector2Array = PackedVector2Array([
		_p(sheet, 0.0, 0.0), _p(sheet, w, 0.0), _p(sheet, w, h - bottom), _p(sheet, 0.0, h - bottom),
	])
	out.add(DrawOp.polyline(outer, PlanTheme.BLACK, line, "frame", "", true))

	if cols > 0:
		var col_w: float = (w - left_band) / float(cols)
		out.add(DrawOp.polyline(PackedVector2Array([_p(sheet, 0.0, top_band), _p(sheet, w, top_band)]), PlanTheme.BLACK, line, "frame"))
		for i: int in cols:
			var x0: float = left_band + col_w * float(i)
			if i > 0:
				out.add(DrawOp.polyline(PackedVector2Array([_p(sheet, x0, 0.0), _p(sheet, x0, top_band)]), PlanTheme.BLACK, line, "frame"))
			out.add(_centered(column_label(i), _p(sheet, x0 + col_w * 0.5, top_band * 0.5), size))
	if rows > 0:
		var row_h: float = (h - bottom - top_band) / float(rows)
		out.add(DrawOp.polyline(PackedVector2Array([_p(sheet, left_band, top_band), _p(sheet, left_band, h - bottom)]), PlanTheme.BLACK, line, "frame"))
		for j: int in rows:
			var y0: float = top_band + row_h * float(j)
			if j > 0:
				out.add(DrawOp.polyline(PackedVector2Array([_p(sheet, 0.0, y0), _p(sheet, left_band, y0)]), PlanTheme.BLACK, line, "frame"))
			out.add(_centered(row_label(j), _p(sheet, left_band * 0.5, y0 + row_h * 0.5), size))


static func _p(sheet: Sheet, page_x: float, page_y_from_top: float) -> Vector2:
	return page_to_world(sheet, page_x, page_y_from_top)


## Text centred on `center` (the baseline sits a little below the centre).
static func _centered(text: String, center: Vector2, size: float) -> DrawOp:
	var op: DrawOp = DrawOp.label(text, center - Vector2(0.0, size * 0.35), size, PlanTheme.BLACK, "frame")
	op.anchor = "center"
	return op
