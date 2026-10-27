class_name UnifilaireLayout
extends RefCounted
## Where everything of the unifilaire goes on its page (SRD 8, FR-UNI-6). Positions are page
## millimetres measured from the top-left corner, y down; the renderer turns them into world
## coordinates. The same layout serves drawing and clicking, so they cannot disagree.
##
## Reading order: the head chain stands at the left, stacked, flowing up into the bus; the bus runs
## to the right along one line; each circuit hangs from it as a column (title, breaker, cable, then
## its points as rows on a ruler shared by all columns); devices sit on the bus line.

const HEAD_W: float = 22.0
const HEAD_H: float = 10.0
const HEAD_GAP: float = 7.0
const DEVICE_W: float = 20.0
const DEVICE_BOX_W: float = 16.0
const DEVICE_BOX_H: float = 10.0
const MIN_COL_W: float = 16.0
const MAX_COL_W: float = 28.0
const BREAKER_W: float = 14.0
const BREAKER_H: float = 15.0
const MAX_ROW_H: float = 15.0
const MIN_ROW_H: float = 9.0
## Distance between the symbols of a chain on a row.
const ITEM_PITCH: float = 8.5

## Offsets below the bus line.
const BREAKER_TOP: float = 3.0
const CABLE_Y: float = 24.0
const CONDUCTOR_TOP: float = 28.0
const ROWS_TOP: float = 38.0
## How far above the bus line the circuit letter and the title go.
const LETTER_UP: float = 22.0
const TITLE_UP: float = 15.0
const HEADER_UP: float = 26.0


class Region:
	extends RefCounted
	var rect: Rect2 = Rect2()
	## "column", "device", "head" or "point".
	var kind: String = ""
	var letter: String = ""
	var index: int = 0
	## Device or head item id.
	var id: String = ""
	var symbol_ids: Array[String] = []


var model: UniModel
var page_w: float = 420.0
var page_h: float = 297.0
var x_head: float = 0.0
var x_ruler: float = 0.0
var x_cols0: float = 0.0
var x_end: float = 0.0
var y_bus: float = 0.0
var y_rows0: float = 0.0
var row_h: float = MAX_ROW_H
var col_w: float = MAX_COL_W
## Per bus item: its x range on the page.
var slot_x: Array[float] = []
var slot_w: Array[float] = []
var regions: Array[Region] = []
var warnings: Array[String] = []


static func compute(doc: Document, sheet: Sheet, model: UniModel) -> UnifilaireLayout:
	var layout: UnifilaireLayout = UnifilaireLayout.new()
	layout.model = model
	var paper_w: int = sheet.props["paper_w_mm"]
	var paper_h: int = sheet.props["paper_h_mm"]
	layout.page_w = float(paper_w)
	layout.page_h = float(paper_h)
	var frame_rows: int = doc.config["frame_rows"]
	var frame_cols: int = doc.config["frame_cols"]
	var left_band: float = PlanTheme.FRAME_BAND if frame_rows > 0 else 0.0
	var top_band: float = PlanTheme.FRAME_BAND if frame_cols > 0 else 0.0
	layout.x_head = left_band + 3.0
	layout.x_cols0 = left_band + 36.0
	layout.x_ruler = layout.x_cols0 - 5.0
	layout.x_end = layout.page_w - 8.0
	layout.y_bus = top_band + 54.0
	layout.y_rows0 = layout.y_bus + ROWS_TOP

	var circuits: int = 0
	var devices: int = 0
	for item: UniModel.BusItem in model.bus:
		if item.is_device:
			devices += 1
		else:
			circuits += 1
	var available: float = layout.x_end - layout.x_cols0
	layout.col_w = clampf((available - float(devices) * DEVICE_W) / float(maxi(circuits, 1)), MIN_COL_W, MAX_COL_W)
	var x: float = layout.x_cols0
	for item: UniModel.BusItem in model.bus:
		var width: float = DEVICE_W if item.is_device else layout.col_w
		layout.slot_x.append(x)
		layout.slot_w.append(width)
		x += width
	if x > layout.x_end + 0.01:
		layout.warnings.append("Le schéma dépasse la largeur de la page")

	var bottom: float = layout.page_h - PlanTheme.CARTOUCHE_HEIGHT - 6.0
	layout.row_h = clampf((bottom - layout.y_rows0) / float(maxi(model.rows, 1)), 1.0, MAX_ROW_H)
	if layout.row_h < MIN_ROW_H:
		layout.warnings.append("Les lignes sont serrées : %d points ne tiennent pas confortablement sur la page" % model.rows)
	layout._build_regions()
	return layout


## Page y of the centre of row `index` (1 is the top row).
func row_center(index: int) -> float:
	return y_rows0 + (float(index) - 0.5) * row_h


## Box of the head item `from_bus` places away from the bus (0 is the one touching the bus line).
func head_box(from_bus: int) -> Rect2:
	var centre_y: float = y_bus + float(from_bus) * (HEAD_H + HEAD_GAP)
	return Rect2(x_head, centre_y - HEAD_H * 0.5, HEAD_W, HEAD_H)


## Right end of the bus line.
func bus_end() -> float:
	if slot_x.is_empty():
		return x_cols0
	return slot_x[slot_x.size() - 1] + slot_w[slot_w.size() - 1]


## Left edge of bus slot `index` (the end of the bus for `index` == the slot count).
func slot_boundary(index: int) -> float:
	if index >= slot_x.size():
		return bus_end()
	return slot_x[index]


## Which place among the bus slots a horizontal position falls in, for dragging (0 to the slot count).
func insertion_index(page_x: float) -> int:
	for i: int in slot_x.size():
		if page_x < slot_x[i] + slot_w[i] * 0.5:
			return i
	return slot_x.size()


## The topmost region at a page position (points above columns), or null.
func hit(page_pos: Vector2) -> Region:
	for i: int in range(regions.size() - 1, -1, -1):
		var region: Region = regions[i]
		if region.rect.has_point(page_pos):
			return region
	return null


func region_of(kind: String, letter: String = "", index: int = 0, id: String = "") -> Region:
	for region: Region in regions:
		if region.kind == kind and region.letter == letter and region.index == index and region.id == id:
			return region
	return null


func _build_regions() -> void:
	for j: int in model.head.size():
		var from_bus: int = model.head.size() - 1 - j
		var head_region: Region = Region.new()
		head_region.kind = "head"
		head_region.id = str(model.head[j]["id"])
		head_region.rect = head_box(from_bus)
		regions.append(head_region)
	for i: int in model.bus.size():
		var item: UniModel.BusItem = model.bus[i]
		var region: Region = Region.new()
		if item.is_device:
			region.kind = "device"
			region.id = item.id
			region.rect = Rect2(slot_x[i], y_bus - 12.0, slot_w[i], 28.0)
		else:
			region.kind = "column"
			region.letter = model.columns[item.column].letter
			region.rect = Rect2(slot_x[i], y_bus - HEADER_UP, slot_w[i], y_rows0 - 2.0 - (y_bus - HEADER_UP))
		regions.append(region)
	for i: int in model.bus.size():
		var item: UniModel.BusItem = model.bus[i]
		if item.is_device:
			continue
		var column: UniModel.Column = model.columns[item.column]
		for point: UniModel.Point in column.sorted_points():
			var cell: Region = Region.new()
			cell.kind = "point"
			cell.letter = column.letter
			cell.index = point.index
			cell.symbol_ids = point.symbol_ids.duplicate()
			cell.rect = Rect2(slot_x[i], y_rows0 + float(point.index - 1) * row_h, slot_w[i], row_h)
			regions.append(cell)
