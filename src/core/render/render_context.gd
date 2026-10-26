class_name RenderContext
extends RefCounted
## Per-sheet conversion facts used by geometry and rendering.

## World millimetres per page millimetre (the 50 of a 1:50 scale).
var scale: float = 50.0
var font_size_pt: float = 10.0
## Default wall line weight, in page mm.
var wall_weight: float = 1.4
## Project-wide display settings (SRD FR-PROJ-1).
var frame_cols: int = 17
var frame_rows: int = 8
var title_pos_mm: Vector2 = Vector2(366, 34)
var ghost_on: bool = false
var hints: bool = true


static func for_sheet(doc: Document, sheet: Sheet) -> RenderContext:
	var ctx: RenderContext = RenderContext.new()
	var den: int = sheet.props["scale_den"]
	ctx.scale = float(den)
	var size: float = doc.config["font_size_pt"]
	ctx.font_size_pt = size
	var weight: float = doc.config["wall_weight_mm"]
	ctx.wall_weight = weight
	ctx.frame_cols = doc.config["frame_cols"]
	ctx.frame_rows = doc.config["frame_rows"]
	ctx.title_pos_mm = EntityGeometry.vec(doc.config["title_pos_mm"])
	ctx.ghost_on = doc.config["ghost_on"]
	ctx.hints = doc.config["hints"]
	return ctx


## Page millimetres to world millimetres.
func page_to_world(page_mm: float) -> float:
	return page_mm * scale


## Typographic points to world millimetres.
func pt_to_world(points: float) -> float:
	return points * PlanTheme.PT_TO_MM * scale
