class_name CartoucheBuilder
extends RefCounted
## The title block at the bottom of every sheet (SRD FR-CART-1 to FR-CART-4). Its layout comes from
## the pack's `cartouche.json`: rows of cells, each with a label and either a project field (`key`)
## or a text with variables. Page millimetres from the top-left corner, like the frame.

const LABEL_FACTOR: float = 0.7
const VALUE_FACTOR: float = 0.95
const PAD: float = 1.6

static var _cache: Dictionary = {}


## The template rows of a pack: Array of Array of {"label", "key"?, "text"?, "weight"}.
static func template(pack_id: String) -> Array:
	if not _cache.has(pack_id):
		_cache[pack_id] = _load("%s/%s/cartouche.json" % [SymbolLibrary.PACKS_DIR, pack_id])
	var rows: Array = _cache[pack_id]
	return rows


## Keys of the project fields the template uses, in order (what the Properties panel edits).
static func field_keys(pack_id: String) -> Array[String]:
	var out: Array[String] = []
	for row: Variant in template(pack_id):
		var cells: Array = row
		for raw: Variant in cells:
			var cell: Dictionary = raw
			var key: String = str(cell.get("key", ""))
			if not key.is_empty() and not out.has(key):
				out.append(key)
	return out


## Key -> label of the project fields (what the Properties panel shows beside each editor).
static func field_labels(pack_id: String) -> Dictionary:
	var out: Dictionary = {}
	for row: Variant in template(pack_id):
		var cells: Array = row
		for raw: Variant in cells:
			var cell: Dictionary = raw
			var key: String = str(cell.get("key", ""))
			if not key.is_empty():
				out[key] = str(cell.get("label", key))
	return out


## `{sheet.name}`, `{page}` ("2/4": position among all sheets) and `{project.<field>}` replaced.
static func expand(text: String, doc: Document, sheet: Sheet) -> String:
	var result: String = text.replace("{sheet.name}", sheet.display_name())
	result = result.replace("{page}", "%d/%d" % [doc.sheet_order.find(sheet.id) + 1, doc.sheet_order.size()])
	for key: Variant in doc.cartouche.keys():
		result = result.replace("{project.%s}" % str(key), str(doc.cartouche[key]))
	# a project field nobody filled in yet is empty, not shown as its variable name
	var unfilled: RegEx = RegEx.create_from_string("\\{project\\.[A-Za-z0-9_]+\\}")
	return unfilled.sub(result, "", true)


static func build(doc: Document, sheet: Sheet, ctx: RenderContext, out: DrawList) -> void:
	var rows: Array = template(doc.pack_ref)
	if rows.is_empty():
		return
	var paper_w: int = sheet.props["paper_w_mm"]
	var paper_h: int = sheet.props["paper_h_mm"]
	var page_w: float = float(paper_w)
	var page_h: float = float(paper_h)
	var top: float = page_h - PlanTheme.CARTOUCHE_HEIGHT
	var row_h: float = PlanTheme.CARTOUCHE_HEIGHT / float(rows.size())
	var line: float = ctx.page_to_world(PlanTheme.FRAME_LINE)
	for r: int in rows.size():
		var cells: Array = rows[r]
		var total: float = 0.0
		for raw: Variant in cells:
			var weight_cell: Dictionary = raw
			total += _weight(weight_cell)
		var x: float = 0.0
		var y: float = top + float(r) * row_h
		for raw: Variant in cells:
			var cell: Dictionary = raw
			var width: float = page_w * _weight(cell) / total
			_add_cell(doc, sheet, ctx, cell, Rect2(x, y, width, row_h), line, out)
			x += width


static func _add_cell(doc: Document, sheet: Sheet, ctx: RenderContext, cell: Dictionary, rect: Rect2, line: float, out: DrawList) -> void:
	var corners: PackedVector2Array = PackedVector2Array([
		_w(sheet, rect.position), _w(sheet, Vector2(rect.end.x, rect.position.y)), _w(sheet, rect.end), _w(sheet, Vector2(rect.position.x, rect.end.y)),
	])
	out.add(DrawOp.polyline(corners, PlanTheme.BLACK, line, "cartouche", "", true))
	# sizes in page mm until the last moment, positions go through _w() which applies the sheet scale
	var label_size: float = ctx.font_size_pt * LABEL_FACTOR * PlanTheme.PT_TO_MM
	out.add(DrawOp.label(str(cell.get("label", "")), _w(sheet, rect.position + Vector2(PAD, PAD + label_size)), ctx.page_to_world(label_size), PlanTheme.PREVIEW_TEXT, "cartouche"))
	var raw_value: String = str(cell.get("text", ""))
	if cell.has("key"):
		raw_value = "{project.%s}" % str(cell["key"])
	var value: String = expand(raw_value, doc, sheet)
	if value.is_empty():
		return
	var size: float = ctx.font_size_pt * VALUE_FACTOR * PlanTheme.PT_TO_MM
	var fit: float = (rect.size.x - 2.0 * PAD) / (float(value.length()) * size * EntityGeometry.TEXT_WIDTH_FACTOR)
	size *= clampf(fit, 0.5, 1.0)
	var at: Vector2 = rect.position + Vector2(PAD, rect.size.y - PAD - size * 0.35)
	out.add(DrawOp.label(value, _w(sheet, at), ctx.page_to_world(size), PlanTheme.BLACK, "cartouche"))


static func _weight(cell: Dictionary) -> float:
	var weight: float = cell.get("weight", 1.0)
	return maxf(weight, 0.01)


static func _w(sheet: Sheet, page: Vector2) -> Vector2:
	return FrameBuilder.page_to_world(sheet, page.x, page.y)


static func _load(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return []
	var data: Dictionary = json.data
	var rows: Variant = data.get("rows", [])
	if rows is Array:
		var list: Array = rows
		return list
	return []
